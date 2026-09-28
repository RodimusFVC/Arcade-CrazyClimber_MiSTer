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
    output logic        dprom_cs
);
    always_comb begin
        {prog_cs, tile0_cs, tile1_cs, bs0_cs, bs1_cs, smp_cs, pal_cs, bspal_cs, dprom_cs} = '0;

        if      (ioctl_addr < 25'h06000) prog_cs  = 1'b1;
        else if (ioctl_addr < 25'h08000) tile0_cs = 1'b1;
        else if (ioctl_addr < 25'h0A000) tile1_cs = 1'b1;
        else if (ioctl_addr < 25'h0A800) bs0_cs   = 1'b1;
        else if (ioctl_addr < 25'h0B000) bs1_cs   = 1'b1;
        else if (ioctl_addr < 25'h0D000) smp_cs   = 1'b1;
        else if (ioctl_addr < 25'h0D040) pal_cs   = 1'b1;
        else if (ioctl_addr < 25'h0D060) bspal_cs = 1'b1;
        else if (ioctl_addr >= 25'h0D100 && ioctl_addr < 25'h0D200) dprom_cs = 1'b1;
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
