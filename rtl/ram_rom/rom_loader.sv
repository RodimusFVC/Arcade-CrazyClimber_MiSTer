//============================================================================
//
//  Crazy Climber ROM loader
//  ROM layout matched to MAME cclimber.cpp regions
//
//============================================================================

// ioctl index 0 (MRA), all images stored exactly as dumped:
//   0x00000 - 0x05FFF  main CPU          "maincpu"   (5 x 4K EPROMs, 4K pad)
//   0x06000 - 0x07FFF  tile plane MSB    "tile"      first half
//   0x08000 - 0x09FFF  tile plane LSB    "tile"      second half
//   0x0A000 - 0x0A7FF  big sprite MSB    "bigsprite" first half
//   0x0A800 - 0x0AFFF  big sprite LSB    "bigsprite" second half
//   0x0B000 - 0x0CFFF  sample ROM        "cclimber_audio:samples"
//   0x0D000 - 0x0D03F  tile/sprite palette PROMs
//   0x0D040 - 0x0D05F  big sprite palette PROM
//   0x0D100 - 0x0D1FF  opcode decryption PROM (dm7052)
//
// ioctl index 1: byte 0 control layout, byte 1 board flags (see the top level)
//
// ioctl index 2 (Swimmer board: swimmer, guzzler, au), all images stored exactly as dumped:
//   0x00000 - 0x07FFF  main CPU 0000-7FFF       "maincpu"
//   0x08000 - 0x09FFF  main CPU E000-FFFF       "maincpu" (Guzzler)
//   0x0A000 - 0x0AFFF  sound CPU                "audiocpu"
//   0x0C000 - 0x11FFF  tile planes MSB..LSB     "tile" (3 x 8K slots; Swimmer/Guzzler fill 4K of each)
//   0x12000 - 0x14FFF  big sprite planes        "bigsprite" (3 x 4K)
//   0x15000 - 0x150FF  palette PROM low nibble  "proms" 0x000 (not on Au: palette RAM)
//   0x15100 - 0x151FF  palette PROM high nibble "proms" 0x100
//   0x15200 - 0x1521F  big sprite palette PROM  "proms" 0x200
//
// ioctl indexes 3 and 4 are reserved for hiscore config and NVRAM
//
// ioctl index 5 (Tangram Q: CC board video, 4K big sprite planes, SNK sound board), images as dumped:
//   0x00000 - 0x05FFF  main CPU                 "maincpu"
//   0x06000 - 0x07FFF  tile plane MSB           "tile" first half
//   0x08000 - 0x09FFF  tile plane LSB           "tile" second half
//   0x0A000 - 0x0AFFF  big sprite plane MSB     "bigsprite" first half
//   0x0B000 - 0x0BFFF  big sprite plane LSB     "bigsprite" second half
//   0x0C000 - 0x0DFFF  sound CPU                "audiocpu"
//   0x0E000 - 0x0E03F  tile/sprite palette PROMs
//   0x0E040 - 0x0E05F  big sprite palette PROM
//
// ioctl index 6 (Yamato: CC board video, Sega 315-5018 CPU, gradient background, polled sound board):
//   0x00000 - 0x07FFF  main CPU 0000-5FFF, 7000-7FFF   "maincpu"
//   0x08000 - 0x09FFF  tile plane MSB                  "tile" first half
//   0x0A000 - 0x0BFFF  tile plane LSB                  "tile" second half
//   0x0C000 - 0x0CFFF  big sprite plane MSB            "bigsprite" first half
//   0x0D000 - 0x0DFFF  big sprite plane LSB            "bigsprite" second half
//   0x0E000 - 0x0E7FF  sound CPU                       "audiocpu"
//   0x10000 - 0x11FFF  gradient ROMs (data0, data1)    "gradient"
//   0x12000 - 0x1203F  palette PROMs 1+2: R/G nibbles  "proms" 0x00
//   0x12040 - 0x1207F  palette PROMs 3+4: B nibble     "proms" 0x40
//   0x12080 - 0x1209F  big sprite palette PROM 5       "proms" 0x80
//
// ioctl index 7 (Top Roller: banked 315-5018 CPU, 12 MHz board; best effort without schematics):
//   0x00000 - 0x0BFFF  "user1" banks 0-2, 0000-3FFF of each (bank n = user1 n*0x6000)
//   0x0C000 - 0x0DFFF  "user1" 0x4000-0x5FFF: the slice MAME ROM_COPYs into every bank (fixed 4000-5FFF)
//   0x10000 - 0x13FFF  main CPU C000-FFFF      "maincpu" 0xC000
//   0x14000 - 0x15FFF  tile plane MSB          "tile" first half
//   0x16000 - 0x17FFF  tile plane LSB          "tile" second half
//   0x18000 - 0x19FFF  big sprite plane MSB    "bigsprite" first half
//   0x1A000 - 0x1BFFF  big sprite plane LSB    "bigsprite" second half
//   0x1C000 - 0x1CFFF  bg plane MSB            "gfx3" first half
//   0x1D000 - 0x1DFFF  bg plane LSB            "gfx3" second half
//   0x1E000 - 0x1FFFF  sample ROM              "cclimber_audio:samples"
//   0x20000 - 0x2009F  palette PROMs (0xA0 pens)
//   0x200A0 - 0x2019F  prom.s9 (likely priority; loaded, not used)

module selector
(
    input  logic [24:0] ioctl_addr,
    output logic        prog_cs,
    output logic        tile0_cs,
    output logic        tile1_cs,
    output logic        bs0_cs,
    output logic        bs1_cs,
    output logic        smp_cs,
    output logic        pal_cs,
    output logic        bspal_cs,
    output logic        dprom_cs,
    output logic        sprom_cs,
    output logic        spch_cs
);
    always_comb begin
        {prog_cs, tile0_cs, tile1_cs, bs0_cs, bs1_cs, smp_cs, pal_cs, bspal_cs, dprom_cs, sprom_cs, spch_cs} = '0;

        if      (ioctl_addr < 25'h06000) prog_cs  = 1'b1;
        else if (ioctl_addr < 25'h08000) tile0_cs = 1'b1;
        else if (ioctl_addr < 25'h0A000) tile1_cs = 1'b1;
        else if (ioctl_addr < 25'h0A800) bs0_cs   = 1'b1;
        else if (ioctl_addr < 25'h0B000) bs1_cs   = 1'b1;
        else if (ioctl_addr < 25'h0D000) smp_cs   = 1'b1;
        else if (ioctl_addr < 25'h0D040) pal_cs   = 1'b1;
        else if (ioctl_addr < 25'h0D060) bspal_cs = 1'b1;
        else if (ioctl_addr >= 25'h0D100 && ioctl_addr < 25'h0D200) dprom_cs = 1'b1;
        else if (ioctl_addr >= 25'h0D200 && ioctl_addr < 25'h0D220) sprom_cs = 1'b1;   // Le Bagnard TMS5110 control PROM
        else if (ioctl_addr >= 25'h0E000 && ioctl_addr < 25'h10000) spch_cs  = 1'b1;   // Le Bagnard speech ROMs (2 x 4K)
    end
endmodule

module selector_swimmer
(
    input  logic [24:0] ioctl_addr,
    output logic        prog_cs,
    output logic        himem_cs,
    output logic        snd_cs,
    output logic  [2:0] tile_cs,
    output logic  [2:0] bs_cs,
    output logic        pal_lo_cs,
    output logic        pal_hi_cs,
    output logic        bspal_cs
);
    always_comb begin
        {prog_cs, himem_cs, snd_cs, tile_cs, bs_cs, pal_lo_cs, pal_hi_cs, bspal_cs} = '0;

        if      (ioctl_addr < 25'h08000) prog_cs   = 1'b1;
        else if (ioctl_addr < 25'h0A000) himem_cs  = 1'b1;
        else if (ioctl_addr < 25'h0B000) snd_cs    = 1'b1;
        else if (ioctl_addr < 25'h0C000) ;
        else if (ioctl_addr < 25'h0E000) tile_cs   = 3'b001;
        else if (ioctl_addr < 25'h10000) tile_cs   = 3'b010;
        else if (ioctl_addr < 25'h12000) tile_cs   = 3'b100;
        else if (ioctl_addr < 25'h13000) bs_cs     = 3'b001;
        else if (ioctl_addr < 25'h14000) bs_cs     = 3'b010;
        else if (ioctl_addr < 25'h15000) bs_cs     = 3'b100;
        else if (ioctl_addr < 25'h15100) pal_lo_cs = 1'b1;
        else if (ioctl_addr < 25'h15200) pal_hi_cs = 1'b1;
        else if (ioctl_addr < 25'h15220) bspal_cs  = 1'b1;
    end
endmodule

module selector_tangramq
(
    input  logic [24:0] ioctl_addr,
    output logic        prog_cs,
    output logic        tile0_cs,
    output logic        tile1_cs,
    output logic        bs0_cs,
    output logic        bs1_cs,
    output logic        snd_cs,
    output logic        pal_cs,
    output logic        bspal_cs
);
    always_comb begin
        {prog_cs, tile0_cs, tile1_cs, bs0_cs, bs1_cs, snd_cs, pal_cs, bspal_cs} = '0;

        if      (ioctl_addr < 25'h06000) prog_cs  = 1'b1;
        else if (ioctl_addr < 25'h08000) tile0_cs = 1'b1;
        else if (ioctl_addr < 25'h0A000) tile1_cs = 1'b1;
        else if (ioctl_addr < 25'h0B000) bs0_cs   = 1'b1;
        else if (ioctl_addr < 25'h0C000) bs1_cs   = 1'b1;
        else if (ioctl_addr < 25'h0E000) snd_cs   = 1'b1;
        else if (ioctl_addr < 25'h0E040) pal_cs   = 1'b1;
        else if (ioctl_addr < 25'h0E060) bspal_cs = 1'b1;
    end
endmodule

module selector_yamato
(
    input  logic [24:0] ioctl_addr,
    output logic        prog_cs,
    output logic        tile0_cs,
    output logic        tile1_cs,
    output logic        bs0_cs,
    output logic        bs1_cs,
    output logic        snd_cs,
    output logic        grad0_cs,
    output logic        grad1_cs,
    output logic        pal_rg_cs,
    output logic        pal_b_cs,
    output logic        bspal_cs
);
    always_comb begin
        {prog_cs, tile0_cs, tile1_cs, bs0_cs, bs1_cs, snd_cs, grad0_cs, grad1_cs, pal_rg_cs, pal_b_cs, bspal_cs} = '0;

        if      (ioctl_addr < 25'h08000) prog_cs   = 1'b1;
        else if (ioctl_addr < 25'h0A000) tile0_cs  = 1'b1;
        else if (ioctl_addr < 25'h0C000) tile1_cs  = 1'b1;
        else if (ioctl_addr < 25'h0D000) bs0_cs    = 1'b1;
        else if (ioctl_addr < 25'h0E000) bs1_cs    = 1'b1;
        else if (ioctl_addr < 25'h0E800) snd_cs    = 1'b1;
        else if (ioctl_addr < 25'h10000) ;
        else if (ioctl_addr < 25'h11000) grad0_cs  = 1'b1;
        else if (ioctl_addr < 25'h12000) grad1_cs  = 1'b1;
        else if (ioctl_addr < 25'h12040) pal_rg_cs = 1'b1;
        else if (ioctl_addr < 25'h12080) pal_b_cs  = 1'b1;
        else if (ioctl_addr < 25'h120A0) bspal_cs  = 1'b1;
    end
endmodule

module selector_toprollr
(
    input  logic [24:0] ioctl_addr,
    output logic        bank_cs,
    output logic        prog_cs,
    output logic        tile0_cs,
    output logic        tile1_cs,
    output logic        bs0_cs,
    output logic        bs1_cs,
    output logic        bg0_cs,
    output logic        bg1_cs,
    output logic        smp_cs,
    output logic        pal_cs
);
    always_comb begin
        {bank_cs, prog_cs, tile0_cs, tile1_cs, bs0_cs, bs1_cs, bg0_cs, bg1_cs, smp_cs, pal_cs} = '0;

        if      (ioctl_addr < 25'h0E000) bank_cs  = 1'b1;
        else if (ioctl_addr < 25'h10000) ;
        else if (ioctl_addr < 25'h14000) prog_cs  = 1'b1;
        else if (ioctl_addr < 25'h16000) tile0_cs = 1'b1;
        else if (ioctl_addr < 25'h18000) tile1_cs = 1'b1;
        else if (ioctl_addr < 25'h1A000) bs0_cs   = 1'b1;
        else if (ioctl_addr < 25'h1C000) bs1_cs   = 1'b1;
        else if (ioctl_addr < 25'h1D000) bg0_cs   = 1'b1;
        else if (ioctl_addr < 25'h1E000) bg1_cs   = 1'b1;
        else if (ioctl_addr < 25'h20000) smp_cs   = 1'b1;
        else if (ioctl_addr < 25'h200A0) pal_cs   = 1'b1;
    end
endmodule
