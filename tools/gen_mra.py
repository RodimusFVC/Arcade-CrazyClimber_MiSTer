#!/usr/bin/env python3
"""Generate MRAs for the Crazy Climber core straight from MAME cclimber.cpp.

Region placement matches rtl/ram_rom/rom_loader.sv; images are copied as dumped
(any decryption/XOR happens in the core).

Release layout: a parent set (MAME parent 0) goes to <releases>/<Title>.mra with the
trailing parentheses dropped; a clone goes to
<releases>/_alternatives/_<Parent Title>/<Full Title>.mra.

Usage:
    gen_mra.py <cclimber.cpp> <releases_dir> [set ...]
"""
import re
import sys
from pathlib import Path

MAME_VERSION = "0289"
HISCORE_DAT = Path("/CybertronMD/Mame/plugins/hiscore/hiscore.dat")   # current file (user, 2026-09-27)
# hiscore.v header after START_WAIT: CHECK_WAIT 00FF, CHECK_HOLD 2, WRITE_HOLD 2, WRITE_REPEATCOUNT 1,
# WRITE_REPEATWAIT 1111, PAUSEPAD 0, CHANGEMASK 0
HISCORE_HEADER_TAIL = "00 FF 00 02 00 02 00 01 11 11 00 00"
# Work RAM survives a core reload, so stale scores can pass the start/end check before the game has run its
# RAM test and table init. START_WAIT must pass the last boot-time write to the table: frame measured in MAME
# (write taps on the hiscore.dat ranges, 30 s), per table layout, + 2 frames: later misses the first score screen.
HISCORE_INIT_FRAME = {"bigkong": 6, "cannonb": 15, "ccboot": 1, "ccboot2": 1, "ccbootmr": 460, "ckong": 6,
                      "guzzler": 111, "rpatrol": 157, "rpatrolb": 157, "silvland": 157, "swimmer": 151,
                      "yamato": 3, "bagmanf": 7}
CLK_HZ, FRAME_HZ = 49_152_000, 60.61

# region -> (base in ioctl index 0, size taken)
REGIONS = {
    "maincpu":                (0x00000, 0x6000),
    "tile":                   (0x06000, 0x4000),
    "bigsprite":              (0x0A000, 0x1000),
    "cclimber_audio:samples": (0x0B000, 0x2000),
    "proms":                  (0x0D000, 0x0060),
    "decryption_prom":        (0x0D100, 0x0100),
    "proms2":                 (0x0D200, 0x0020),       # Le Bagnard TMS5110 control PROM
    "speech":                 (0x0E000, 0x2000),       # Le Bagnard speech ROMs
}

# ---------------------------------------------------------------- per-family setup

# Swimmer board (machine swimmer/guzzler) loads through ioctl index 2 with its own map
SWIMMER_MACHINES = {"swimmer", "guzzler", "au"}
def variant_for(g):
    """Index 1 byte 2: [0] Au, [1] Cannon Ball board, [2] Cannon Ball first-ROM XOR (init_cannonb)."""
    if g["machine"] == "au":
        return 0x01
    if g["machine"] == "cannonb":
        return 0x02 | (0x04 if g["init"] == "init_cannonb" else 0)
    if g["machine"] == "tangramq":
        return 0x08
    if g["machine"] == "yamato":
        return 0x10
    if g["machine"] == "toprollr":
        return 0x20
    if g["machine"] == "bagmanf":
        return 0x40
    return None


# Tangram Q loads through ioctl index 5 (indexes 3/4 are reserved for hiscore config / NVRAM)
TANGRAMQ_REGIONS = {"maincpu": 0x00000, "tile": 0x06000, "bigsprite": 0x0A000, "audiocpu": 0x0C000, "proms": 0x0E000}
# Yamato loads through ioctl index 6
YAMATO_REGIONS = {"maincpu": 0x00000, "tile": 0x08000, "bigsprite": 0x0C000, "audiocpu": 0x0E000,
                  "gradient": 0x10000, "proms": 0x12000}


def toprollr_region(region, dst):
    """Top Roller ioctl index 7 (see rom_loader.sv). user1 = 3 banks of 0x6000 whose top 8K is the same ROM."""
    if region == "maincpu":
        return 0x10000 + dst - 0xC000 if dst >= 0xC000 else None
    if region == "user1":
        bank, off = divmod(dst, 0x6000)
        return bank * 0x4000 + off if off < 0x4000 else 0x0C000 + off - 0x4000
    base = {"tile": 0x14000, "bigsprite": 0x18000, "gfx3": 0x1C000,
            "cclimber_audio:samples": 0x1E000, "proms": 0x20000}.get(region)
    return None if base is None else base + dst


def rom_index_for(g):
    if g["machine"] in SWIMMER_MACHINES:
        return 2
    if g["machine"] == "tangramq":
        return 5
    if g["machine"] == "yamato":
        return 6
    if g["machine"] == "toprollr":
        return 7
    return 0
IGNORED_REGIONS = {"cpu_pal", "unused"}            # guzzlers' PAL16L8 dump, cannonb's stray ROMs


def swimmer_region(region, dst, rsize):
    """ioctl address for a Swimmer-board load (see rom_loader.sv), or None if the region is unknown."""
    if region == "maincpu":
        if dst < 0x8000:
            return dst
        if dst >= 0xE000:
            return 0x8000 + (dst - 0xE000)
        return None
    if region == "audiocpu" and dst < 0x1000:
        return 0x0A000 + dst
    if region in ("tile", "bigsprite"):
        plane = rsize // 3                                  # RGN_FRAC(1,3) planes, MSB first
        slot = 0x2000 if region == "tile" else 0x1000
        base = 0x0C000 if region == "tile" else 0x12000
        return base + (dst // plane) * slot + dst % plane
    if region == "proms":
        return 0x15000 + dst
    return None


LAYOUT_CC, LAYOUT_CKONG, LAYOUT_RPATROL, LAYOUT_SWIMMER, LAYOUT_CANNONB, LAYOUT_TANGRAMQ, LAYOUT_YAMATO, LAYOUT_TOPROLLR = \
    0, 1, 2, 3, 4, 5, 6, 7

F_DECRYPT, F_VOL5, F_VERT, F_NMIQ3, F_SWIMMER, F_ROT90 = 0x01, 0x08, 0x10, 0x20, 0x40, 0x80
XOR = {"init_rpatrol": 1 << 1, "init_ckongb": 2 << 1, "init_dking": 3 << 1}

BUTTONS = {
    LAYOUT_TOPROLLR: ("Button 1,Not Used,Not Used,Not Used,Coin,Start 1P,Start 2P,Pause", "A,Y,B,X,Select,Start,R,L", 1, "4-way", ""),
    LAYOUT_YAMATO: ("Button 1,Button 2,Not Used,Not Used,Coin,Start 1P,Start 2P,Pause", "A,Y,B,X,Select,Start,R,L", 2, "8-way", ""),
    LAYOUT_TANGRAMQ: ("Button 1,Not Used,Not Used,Not Used,Coin,Start 1P,Start 2P,Pause", "A,Y,B,X,Select,Start,R,L", 1, "2-way horizontal", ""),
    LAYOUT_CANNONB: ("Fire,Not Used,Not Used,Not Used,Coin,Start 1P,Start 2P,Pause", "A,Y,B,X,Select,Start,R,L", 1, "4-way", ""),
    LAYOUT_SWIMMER: ("Button 1,Not Used,Not Used,Not Used,Coin,Start 1P,Start 2P,Pause", "A,Y,B,X,Select,Start,R,L", 1, "8-way", ""),
    LAYOUT_CC:      ("R Right,R Left,R Down,R Up,Coin,Start 1P,Start 2P,Pause", "A,Y,B,X,Select,Start,R,L", 4, "8-way", "twin stick"),
    LAYOUT_CKONG:   ("Jump,Not Used,Not Used,Not Used,Coin,Start 1P,Start 2P,Pause", "A,Y,B,X,Select,Start,R,L", 1, "4-way", ""),
    LAYOUT_RPATROL: ("Gas,Not Used,Not Used,Not Used,Coin,Start 1P,Start 2P,Pause", "A,Y,B,X,Select,Start,R,L", 1, "2-way horizontal", ""),
}

CC_COMMON = [
    ('Rack Test (Cheat)', "3", "Off,On"),
    ('Coin A', "4,5", "1C/1C,2C/1C,3C/1C,4C/1C"),
    ('Coin B', "6,7", "1C/1C,1C/2C,1C/3C,Free Play"),
    ('Cabinet', "8", "Cocktail,Upright"),
]
CKONG_COMMON = [
    ('Bonus Life', "2,3", "7000,10000,15000,20000"),
    ('Coinage', "4,6", "1C/1C,2C/1C,1C/2C,3C/1C,1C/3C,4C/1C,1C/4C,5C/1C"),
    ('Cabinet', "7", "Cocktail,Upright"),
]

# INPUT_PORTS name -> (switch default, dip list)
SW_COIN = [('Coin A', "4,5", "1C/1C,2C/1C,1C/2C,1C/3C"),
           ('Coin B', "6,7", "1C/1C,1C/2C,1C/3C,1C/6C"),
           ('Cabinet', "12", "Cocktail,Upright")]

YM_DSW1 = [('Lives', "0,1", "3,4,5,6"),
           ('Coin A', "2,4", "1C/1C,2C/1C,3C/1C,4C/1C,1C/2C,1C/3C,2C/3C,Free Play"),
           ('Bonus Life', "5", "Every 30000,Every 50000"),
           ('Speed', "6", "Slow,Fast"),
           ('Cabinet', "7", "Cocktail,Upright")]

DIPS = {
    "toprollr": ("80,00", [('Lives', "0,1", "3,4,5,6"),
                           ('Coin A', "2,4", "1C/1C,2C/1C,3C/1C,4C/1C,1C/2C,1C/3C,2C/3C,Free Play"),
                           ('Bonus Life', "5", "Every 30000,Every 50000"),
                           ('Difficulty', "6", "Easy,Hard"),
                           ('Cabinet', "7", "Cocktail,Upright"),
                           ('Coin B', "8,10", "1C/1C,Invalid,3C/1C,4C/1C,1C/2C,1C/3C,2C/3C,Free Play")]),
    "yamato":   ("80,00", YM_DSW1),
    "yamatou":  ("80,00", YM_DSW1 + [('Coin B', "8,10", "1C/1C,2C/1C,3C/1C,4C/1C,1C/2C,1C/3C,2C/3C,Free Play")]),
    "tangramq": ("8E,FF", [('Lives', "0,1", "1,2,3,5"),
                           ('Freeze', "2", "On,Off"),
                           ('Demo Sounds', "3", "Off,On"),
                           ('Coinage', "4,6", "1C/1C,1C/2C,1C/3C,1C/5C,1C/6C,2C/1C,3C/1C,4C/1C"),
                           ('Cabinet', "7", "Cocktail,Upright"),
                           ('Free Play', "11", "On,Off"),
                           ('Infinite Lives', "12", "On,Off")]),
    "cannonb":  ("E7",    [('Display', "0,1", "None,Scores Only,Progress Bars Only,Scores and Progress Bars"),
                           ('Cabinet', "2", "Cocktail,Upright"),
                           ('Lives', "3,4", "3,4,5,6")]),
    "swimmer":  ("00,30", [('Lives', "0,1", "3,4,5,Infinite (Cheat)"),
                           ('Bonus Life', "2,3", "10000,20000,30000,None")] + SW_COIN +
                          [('Demo Sounds', "13", "Off,On"),
                           ('Difficulty', "14,15", "Easy,Hard,Harder,Hardest")]),
    "swimmerb": ("00,70", [('Lives', "0,1", "3,4,5,Infinite (Cheat)"),
                           ('Bonus Life', "2,3", "10000,20000,30000,None")] + SW_COIN +
                          [('Demo Sounds', "13", "Off,On"),
                           ('Difficulty', "14", "Easy,Hard")]),
    "au":       ("00,80", [('Coin A', "0,1", "1C/1C,1C/2C,1C/3C,Disabled"),
                           ('Coin B', "2,3", "1C/1C,2C/1C,1C/2C,1C/3C"),
                           ('Bonus Life', "4,5", "30K 100K Every 100K,20K 50K Every 50K,30K,None"),
                           ('Lives', "6,7", "3,4,5,Infinite (Cheat)"),
                           ('Cabinet', "15", "Cocktail,Upright")]),
    "guzzler":  ("00,10", [('Lives', "0,1", "3,4,5,Infinite (Cheat)"),
                           ('Bonus Life', "2,3", "30K Every 100K,20K Every 50K,30K Only,None")] + SW_COIN +
                          [('High Score Names', "13", "10 Letters,3 Letters"),
                           ('Difficulty', "14,15", "Easy,Medium,Hard,Hardest")]),
    "cclimber":  ("00,01", [('Lives', "0,1", "3,4,5,6")] + CC_COMMON),
    "cclimberj": ("00,01", [('Lives', "0,1", "3,4,5,6"), ('Bonus Life', "2", "30000,50000")] + CC_COMMON),
    "ckong":     ("80",    [('Lives', "0,1", "3,4,5,6")] + CKONG_COMMON),
    "ckongb":    ("80",    [('Lives', "0,1", "1,2,3,4")] + CKONG_COMMON),
    "ckongb2":   ("80",    [('Lives', "0,1", "2,3,4,5")] + CKONG_COMMON),
    "bagmanf":   ("FE",    [('Lives', "0,1", "5,4,3,2"),
                            ('Coinage', "2", "2C/1C 1C/1C 1C/3C 1C/7C,1C/1C 1C/2C 1C/6C 1C/14C"),
                            ('Difficulty', "3,4", "Hardest,Hard,Medium,Easy"),
                            ('Language', "5", "French,English"),
                            ('Bonus Life', "6", "40000,30000"),
                            ('Cabinet', "7", "Cocktail,Upright")]),
    "rpatrol":   ("90",    [('Coinage', "0,1", "1C/1C,1C/2C,2C/1C,Free Play"),
                            ('Lives', "2,3", "3,4,5,6"),
                            ('Cabinet', "4", "Cocktail,Upright"),
                            ('Unknown 1', "5", "Off,On"),
                            ('Unknown 2', "6", "Off,On"),
                            ('Memory Test', "7", "Retry on Error,Stop on Error")]),
}

SERIES = {LAYOUT_CC: ("Crazy Climber", "Platform - Climb"),
          LAYOUT_CKONG: ("Crazy Kong", "Platform"),
          LAYOUT_RPATROL: ("River Patrol", "Shooter")}

REGION_WORDS = [("US", "US"), ("Japan", "Japan"), ("Spanish", "Spain")]

JOYSTICK_BY_INPUT = {"guzzler": "4-way"}

SERIES_BY_PARENT = {"bagman": ("Bagman", "Platform"), "toprollr": ("Top Roller", "Driving"), "yamato": ("Yamato", "Shooter"), "tangramq": ("Tangram Q", "Puzzle"), "cannonbp": ("Cannon Ball", "Shooter"), "swimmer": ("Swimmer", "Action"), "guzzler": ("Guzzler", "Maze"), "au": ("Au", "Action")}

LAYOUT_BY_INPUT = {"toprollr": LAYOUT_TOPROLLR, "yamato": LAYOUT_YAMATO, "yamatou": LAYOUT_YAMATO, "tangramq": LAYOUT_TANGRAMQ, "cannonb": LAYOUT_CANNONB, "au": LAYOUT_SWIMMER, "swimmer": LAYOUT_SWIMMER, "swimmerb": LAYOUT_SWIMMER, "guzzler": LAYOUT_SWIMMER,
                   "cclimber": LAYOUT_CC, "cclimberj": LAYOUT_CC,
                   "ckong": LAYOUT_CKONG, "ckongb": LAYOUT_CKONG, "ckongb2": LAYOUT_CKONG, "bagmanf": LAYOUT_CKONG,
                   "rpatrol": LAYOUT_RPATROL}

# ---------------------------------------------------------------- parsing

GAME_RE = re.compile(r'^GAME\(\s*(\d+),\s*(\w+),\s*(\w+),\s*(\w+),\s*(\w+),\s*\w+,\s*(\w+),\s*(ROT\d+),\s*"([^"]*)",\s*"([^"]*)"', re.M)
LOAD_RE = re.compile(r'ROM_LOAD\(\s*"([^"]+)",\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+),\s*(?:BAD_DUMP\s+)?CRC\(([0-9a-fA-F]+)\)')
CONT_RE = re.compile(r'ROM_CONTINUE\(\s*(0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+)\s*\)')
REGION_RE = re.compile(r'ROM_REGION\(\s*(0x[0-9a-fA-F]+),\s*"([^"]+)"')


def parse_hiscores(path):
    """hiscore.dat -> {set: [(addr, len, start, end)]}; sets listed together share the entry lines below them."""
    out, names, body = {}, [], False
    for line in path.read_text(encoding="latin-1").splitlines():
        line = line.strip()
        if not line or line.startswith(";"):
            names, body = ([], False) if not line else (names, body)
            continue
        if line.endswith(":"):
            if body:
                names, body = [], False
            names.append(line[:-1])
        elif line.startswith("@"):
            for n in names:
                out.setdefault(n, []).append(line)
            body = True
    return out


HISCORES = parse_hiscores(HISCORE_DAT) if HISCORE_DAT.exists() else {}


def hiscore_xml(g):
    lines = HISCORES.get(g["name"])
    if not lines:
        return ""
    ents = []
    for line in lines:
        f = line.split(",")
        if f[0] != "@:maincpu" or f[1] != "program":
            raise SystemExit(f'{g["name"]}: unsupported hiscore.dat line {line}')
        ents.append((int(f[2], 16), int(f[3], 16), int(f[4], 16), int(f[5], 16)))
    rows = "\n".join(f"            {a >> 24 & 0xFF:02X} {a >> 16 & 0xFF:02X} {a >> 8 & 0xFF:02X} {a & 0xFF:02X} "
                      f"{n >> 8:02X} {n & 0xFF:02X} {s:02X} {e:02X}" for a, n, s, e in ents)
    total = sum(n for _, n, _, _ in ents)
    ref = next((k for k in HISCORE_INIT_FRAME if HISCORES.get(k) == lines), None)
    if ref is None:
        raise SystemExit(f'{g["name"]}: no measured table-init frame for this hiscore layout')
    wait = round((HISCORE_INIT_FRAME[ref] + 2) / FRAME_HZ * CLK_HZ)
    header = " ".join(f"{b:02X}" for b in wait.to_bytes(4, "big")) + " " + HISCORE_HEADER_TAIL
    return f"""
    <!-- Index 3: hiscore config (MAME hiscore.dat), index 4: saved scores -->
    <rom index="3" md5="none">
        <part>
            {header}
{rows}
        </part>
    </rom>
    <rom index="4"></rom>
    <nvram index="4" size="{total}"></nvram>
"""


def parse_games(src):
    games = {}
    for m in GAME_RE.finditer(src):
        year, name, parent, machine, inputs, init, rot, manuf, desc = m.groups()
        games[name] = dict(year=year, name=name, parent=None if parent == "0" else parent,
                           machine=machine, inputs=inputs, init=init, rot=rot, manuf=manuf, desc=desc)
    return games


def parse_roms(src, setname):
    m = re.search(r'ROM_START\(\s*%s\s*\)(.*?)ROM_END' % re.escape(setname), src, re.S)
    if not m:
        raise SystemExit(f"ROM_START({setname}) not found")
    segs, region, rsize, last = [], None, 0, None
    for line in m.group(1).splitlines():
        line = line.split("//")[0]
        if (r := REGION_RE.search(line)):
            region, rsize, last = r.group(2), int(r.group(1), 16), None
        elif (l := LOAD_RE.search(line)):
            name, off, length, crc = l.group(1), int(l.group(2), 16), int(l.group(3), 16), l.group(4).lower()
            last = dict(name=name, crc=crc, src=0, dst=off, len=length, region=region, rsize=rsize)
            segs.append(last)
        elif (c := CONT_RE.search(line)):
            off, length = int(c.group(1), 16), int(c.group(2), 16)
            nxt = dict(last, src=last["src"] + last["len"], dst=off, len=length)
            segs.append(nxt)
            last = nxt
        elif "ROM_COPY" in line and setname == "toprollr":
            continue                                   # the copied slice is one fixed ROM on the board (rom_loader.sv)
        elif "ROM_" in line and ("ROM_LOAD" in line or "ROM_COPY" in line or "ROM_FILL" in line):
            raise SystemExit(f"{setname}: unhandled ROM statement: {line.strip()}")
    return segs


def place(segs, setname, swimmer=False, tangramq=False, yamato=False, toprollr=False):
    out = []
    for s in segs:
        if s["region"] in IGNORED_REGIONS:
            continue
        if toprollr:
            hit = toprollr_region(s["region"], s["dst"])
            if hit is None:
                raise SystemExit(f"{setname}: unmapped region {s['region']} @ 0x{s['dst']:X}")
            out.append(dict(s, addr=hit))
            continue
        if tangramq or yamato:
            table = TANGRAMQ_REGIONS if tangramq else YAMATO_REGIONS
            if s["region"] not in table:
                raise SystemExit(f"{setname}: unmapped region {s['region']}")
            out.append(dict(s, addr=table[s["region"]] + s["dst"]))
            continue
        if swimmer:
            hit = swimmer_region(s["region"], s["dst"], s["rsize"])
            if hit is None:
                raise SystemExit(f"{setname}: unmapped region {s['region']} @ 0x{s['dst']:X}")
            out.append(dict(s, addr=hit))
            continue
        if s["region"] not in REGIONS:
            raise SystemExit(f"{setname}: unmapped region {s['region']}")
        if s["region"] == "maincpu" and s["dst"] >= 0x10000:
            s = dict(s, dst=s["dst"] - 0x10000)              # cannonb stages its encrypted ROM at 0x10000
        base, size = REGIONS[s["region"]]
        if s["dst"] >= size:
            continue                                   # e.g. dking's extra 82s129 past the palette PROMs
        if s["dst"] + s["len"] > size:
            raise SystemExit(f"{setname}: {s['name']} overruns {s['region']}")
        out.append(dict(s, addr=base + s["dst"]))
    out.sort(key=lambda s: s["addr"])
    for a, b in zip(out, out[1:]):
        assert a["addr"] + a["len"] <= b["addr"], f"{setname}: overlap {a['name']} / {b['name']}"
    return out


def whole_file(seg, segs):
    """True when this segment is the file's only load (no ROM_CONTINUE pieces)."""
    return sum(1 for s in segs if s["name"] == seg["name"] and s["crc"] == seg["crc"]) == 1 and seg["src"] == 0

# ---------------------------------------------------------------- output

def flags_for(g, segs):
    f = 0
    regions = {s["region"] for s in segs}
    if g["init"] == "init_cclimber" and "decryption_prom" in regions:
        f |= F_DECRYPT
    f |= XOR.get(g["init"], 0)
    layout = LAYOUT_BY_INPUT[g["inputs"]]
    if layout in (LAYOUT_CKONG, LAYOUT_CANNONB, LAYOUT_TOPROLLR):
        f |= F_VOL5                                    # Falcon redraw shows the D4 resistor fitted
    if g["rot"] in ("ROT90", "ROT270"):
        f |= F_VERT
    if g["rot"] == "ROT90":
        f |= F_ROT90
    if g["machine"] in SWIMMER_MACHINES:
        f |= F_SWIMMER
    if g["machine"] == "ckongb":
        f |= F_NMIQ3
    return layout, f


def mra(g, games, segs):
    layout, flags = flags_for(g, segs)
    names, default, nbtn, joy, special = BUTTONS[layout]
    joy = JOYSTICK_BY_INPUT.get(g["inputs"], joy)
    sw_default, dips = DIPS[g["inputs"]]
    parent = g["parent"] or g["name"]
    zipname = f'{g["name"]}.zip' + (f'|{g["parent"]}.zip' if g["parent"] else "")
    rotation = {"ROT0": "horizontal", "ROT270": "vertical (ccw)", "ROT90": "vertical (cw)"}[g["rot"]]
    bootleg = "yes" if "bootleg" in g["manuf"].lower() or "hack" in g["desc"].lower() else "no"
    series, category = SERIES_BY_PARENT.get(parent, SERIES.get(layout))
    region = next((r for w, r in REGION_WORDS if w in g["desc"]), "World")
    has_dprom = any(s["region"] == "decryption_prom" for s in segs)
    rom_index = rom_index_for(g)
    v = variant_for(g)
    variant = f" {v:02X}" if v is not None else ""
    if rom_index == 7:
        index0 = ("banks 0x0000 (3 x 16K), fixed 4000-5FFF 0xC000, CPU C000-FFFF 0x10000, tiles 0x14000, "
                  "big sprite 0x18000, bg 0x1C000, samples 0x1E000, PROMs 0x20000")
    elif rom_index == 6:
        index0 = ("CPU 0x0000, tiles 0x8000, big sprite 0xC000, sound CPU 0xE000, gradient 0x10000, "
                  "palette PROMs 0x12000")
    elif rom_index == 5:
        index0 = "CPU 0x0000, tiles 0x6000, big sprite 0xA000, sound CPU 0xC000, palette PROMs 0xE000"
    elif rom_index == 2:
        index0 = ("CPU 0x0000 + E000 at 0x8000, sound CPU 0xA000, tile planes 0xC000 (8K slots), "
                  "big sprite 0x12000" + (", palette PROMs 0x15000" if any(s["region"] == "proms" for s in segs) else ""))
    else:
        index0 = ("CPU 0x0000, tiles 0x6000, big sprite 0xA000, samples 0xB000, palette PROMs 0xD000"
                  + (", decryption PROM 0xD100" if has_dprom else "")
                  + (", speech PROM 0xD200, speech ROMs 0xE000" if any(s["region"] == "speech" for s in segs) else ""))

    lines = []
    pos = 0
    for s in segs:
        if s["addr"] > pos:
            lines.append(f'        <part repeat="0x{s["addr"] - pos:X}">00</part>')
        if whole_file(s, segs):
            lines.append(f'        <part crc="{s["crc"]}" name="{s["name"]}"/>')
        else:
            lines.append(f'        <part crc="{s["crc"]}" name="{s["name"]}" offset="0x{s["src"]:X}" length="0x{s["len"]:X}"/>')
        pos = s["addr"] + s["len"]

    dip_lines = "\n".join(f'        <dip name="{n}" bits="{b}" ids="{i}"/>' for n, b, i in dips)
    return f"""<misterromdescription>
    <name>{display_name(g)}</name>
    <region>{region}</region>
    <homebrew>no</homebrew>
    <bootleg>{bootleg}</bootleg>
    <version></version>
    <alternative></alternative>
    <platform></platform>
    <series>{series}</series>
    <year>{g["year"]}</year>
    <manufacturer>{g["manuf"]}</manufacturer>
    <category>{category}</category>

    <setname>{g["name"]}</setname>
    <parent>{parent}</parent>
    <mameversion>{MAME_VERSION}</mameversion>
    <rbf>CrazyClimber</rbf>
    <about></about>

    <resolution>15kHz</resolution>
    <rotation>{rotation}</rotation>
    <flip>no</flip>

    <players>2 (alternating)</players>
    <joystick>{joy}</joystick>
    <special_controls>{special}</special_controls>
    <num_buttons>{nbtn}</num_buttons>
    <buttons names="{names}" default="{default}"/>

    <switches default="{sw_default}">
{dip_lines}
    </switches>

    <!-- Index {rom_index}: {index0} -->
    <rom index="{rom_index}" md5="none" zip="{zipname}">
{chr(10).join(lines)}
    </rom>

    <!-- Index 1: control layout, board flags (see Arcade-CrazyClimber.sv) -->
    <rom index="1">
        <part>{layout:02X} {flags:02X}{variant}</part>
    </rom>
{hiscore_xml(g)}
    <remark>{remark(g)}</remark>
    <mratimestamp>20260927000000</mratimestamp>
</misterromdescription>
"""


SMALL_WORDS = {"a", "an", "and", "as", "at", "by", "for", "in", "of", "on", "or", "the", "to", "vs"}


def title_case(text):
    """Capitalise each word, keep acronyms (US, II, PCB), leave small words lower unless first."""
    out = []
    for i, word in enumerate(re.split(r"(\s+|[()/,-])", text)):
        if word and word[0].isalpha() and (i == 0 or word.lower() not in SMALL_WORDS):
            word = word[0].upper() + word[1:]
        out.append(word)
    return "".join(out)


def clean_title(desc):
    """Parent title: the description without its trailing parenthesised qualifiers."""
    return re.sub(r"(\s*\([^()]*\))+$", "", desc).strip()


def display_name(g):
    return title_case(clean_title(g["desc"]) if g["parent"] is None else g["desc"])


def remark(g):
    """'Title (Maker)', without repeating a maker the title already names."""
    m = re.fullmatch(r'bootleg \((.+)\)', g["manuf"])
    maker = f"{m.group(1)} bootleg" if m else g["manuf"]
    desc = title_case(g["desc"])
    return desc if maker.lower() in g["desc"].lower() else f"{desc} ({title_case(maker)})"


def safe(name):
    return re.sub(r'\s*/\s*', " - ", re.sub(r'[\\:*?"<>|]', "-", name))


def out_path(root, g, games):
    if g["parent"] is None:
        return root / f"{safe(display_name(g))}.mra"
    # a parent in another MAME driver (cannonbp is Pac-Man hardware) still names the folder
    parent_title = display_name(games[g["parent"]]) if g["parent"] in games else title_case(clean_title(g["desc"]))
    return root / "_alternatives" / f"_{safe(parent_title)}" / f"{safe(display_name(g))}.mra"


def main():
    src = Path(sys.argv[1]).read_text()
    out_dir = Path(sys.argv[2])
    games = parse_games(src)
    for name in sys.argv[3:]:
        g = games[name]
        segs = place(parse_roms(src, name), name, g["machine"] in SWIMMER_MACHINES, g["machine"] == "tangramq",
                     g["machine"] == "yamato", g["machine"] == "toprollr")
        path = out_path(out_dir, g, games)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(mra(g, games, segs))
        print(f'{name:12s} {LAYOUT_BY_INPUT[g["inputs"]]:02X} {flags_for(g, segs)[1]:02X}  {path.relative_to(out_dir)}')


if __name__ == "__main__":
    main()
