//============================================================================
//
//  Crazy Climber dispatcher: ROM load map, shared CPU / sound chip / ROM / RAM pools, and the board
//  (rtl/boards/cclimber/cclimber_main.sv, which carries the sound boards and the Top Roller video)
//  Copyright (C) 2026 Rodimus
//
//  Video timing and scanout pipeline ported from Crazy Climber FPGA by
//  Dar (darfpga@aol.fr, http://darfpga.blogspot.fr)
//  Memory maps, opcode decryption and sound model per MAME cclimber.cpp
//  (Nicola Salmoria)
//
//============================================================================

module cclimber_dispatcher
(
    input               clk,            // 49.152 MHz
    input               reset,          // active high
    input               ce12,           // 12.288 MHz enable = 2x pixel
    input               pause,

    input               swimmer,        // Swimmer board (3bpp, sound CPU)
    input               au,             // Au: Swimmer board with 8K planes and palette RAM
    input               cannonb,        // Cannon Ball: CK board, chars/sprites split per plane, one flip bit
    input               cb_xor,         // Cannon Ball set 1: first program ROM XORed by address
    input               tangramq,       // Tangram Q: SYSTEM ports at 8000/8020, SNK sound board, 4K big sprite planes
    input               yamato,         // Yamato: Sega 315-5018 CPU, 12-bit palette, gradient background, polled sound board
    input               toprollr,       // Top Roller: banked 315-5018 CPU, extra bg layer, 56 sprites (toprollr_video.sv)
    input               bagmanf,        // Le Bagnard: Bagman map on the CK board, TMS5110 speech
    input               decrypt_en,     // dm7052 opcode decryption PROM fitted
    input         [1:0] rom_xor,        // 0 none, 1 rpatrol, 2 ckongb, 3 dking
    input               vol5_en,        // volume D4 resistor fitted
    input               nmi_q3,         // latch Q3 also drives the NMI mask (ckongb bootleg)

    input         [7:0] in_p1,          // $A000
    input         [7:0] in_p2,          // $A800
    input         [7:0] in_dsw,         // $B000
    input         [7:0] in_sys,         // $B800
    input         [7:0] in_sys1,        // $8000 (Tangram Q)
    input         [7:0] in_sys2,        // $8020 (Tangram Q)

    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               ioctl_wr0,      // ioctl index 0 (Crazy Climber layout)
    input               ioctl_wr2,      // ioctl index 2 (Swimmer layout)
    input               ioctl_wr5,      // ioctl index 5 (Tangram Q layout)
    input               ioctl_wr6,      // ioctl index 6 (Yamato layout)
    input               ioctl_wr7,      // ioctl index 7 (Top Roller layout)

    output        [7:0] video_r,
    output        [7:0] video_g,
    output        [7:0] video_b,
    output              video_hs,
    output              video_vs,
    output              video_hblank,
    output              video_vblank,
    output              ce_pix,

    input               crt_flip,       // OSD CRT Flip, XORed with the game's flip latch
    input  signed [3:0] h_adj,          // CRT position: HSYNC moved 2 pixels per step
    input  signed [3:0] v_adj,          //               VSYNC moved 1 line per step

    output              flip_x,
    output              flip_y,

    output signed [15:0] audio,

    // hiscore: second port on the work RAMs and video RAM (CPU addresses)
    input        [15:0] hs_address,
    input         [7:0] hs_data_in,
    output        [7:0] hs_data_out,
    input               hs_write
);

//------------------------------------------------------- ROM load map --------------------------------------------------------//

// Layouts in rtl/ram_rom/rom_loader.sv
wire prog_cs, tile0_cs, tile1_cs, bs0_cs, bs1_cs, smp_cs, pal_cs, bspal_cs, dprom_cs, sprom_cs, spch_cs;

selector rom_sel
(
    .ioctl_addr(ioctl_addr),
    .prog_cs(prog_cs),
    .tile0_cs(tile0_cs),
    .tile1_cs(tile1_cs),
    .bs0_cs(bs0_cs),
    .bs1_cs(bs1_cs),
    .smp_cs(smp_cs),
    .pal_cs(pal_cs),
    .bspal_cs(bspal_cs),
    .dprom_cs(dprom_cs),
    .sprom_cs(sprom_cs),
    .spch_cs(spch_cs)
);

wire       sw_prog_cs, sw_himem_cs, sw_snd_cs, sw_pal_lo_cs, sw_pal_hi_cs, sw_bspal_cs;
wire [2:0] sw_tile_cs, sw_bs_cs;

selector_swimmer rom_sel_sw
(
    .ioctl_addr(ioctl_addr),
    .prog_cs(sw_prog_cs),
    .himem_cs(sw_himem_cs),
    .snd_cs(sw_snd_cs),
    .tile_cs(sw_tile_cs),
    .bs_cs(sw_bs_cs),
    .pal_lo_cs(sw_pal_lo_cs),
    .pal_hi_cs(sw_pal_hi_cs),
    .bspal_cs(sw_bspal_cs)
);

wire tq_prog_cs, tq_tile0_cs, tq_tile1_cs, tq_bs0_cs, tq_bs1_cs, tq_snd_cs, tq_pal_cs, tq_bspal_cs;

selector_tangramq rom_sel_tq
(
    .ioctl_addr(ioctl_addr),
    .prog_cs(tq_prog_cs),
    .tile0_cs(tq_tile0_cs),
    .tile1_cs(tq_tile1_cs),
    .bs0_cs(tq_bs0_cs),
    .bs1_cs(tq_bs1_cs),
    .snd_cs(tq_snd_cs),
    .pal_cs(tq_pal_cs),
    .bspal_cs(tq_bspal_cs)
);

wire dl_tq_snd = ioctl_wr5 & tq_snd_cs;

wire ym_prog_cs, ym_tile0_cs, ym_tile1_cs, ym_bs0_cs, ym_bs1_cs, ym_snd_cs, ym_grad0_cs, ym_grad1_cs;
wire ym_pal_rg_cs, ym_pal_b_cs, ym_bspal_cs;

selector_yamato rom_sel_ym
(
    .ioctl_addr(ioctl_addr),
    .prog_cs(ym_prog_cs),
    .tile0_cs(ym_tile0_cs),
    .tile1_cs(ym_tile1_cs),
    .bs0_cs(ym_bs0_cs),
    .bs1_cs(ym_bs1_cs),
    .snd_cs(ym_snd_cs),
    .grad0_cs(ym_grad0_cs),
    .grad1_cs(ym_grad1_cs),
    .pal_rg_cs(ym_pal_rg_cs),
    .pal_b_cs(ym_pal_b_cs),
    .bspal_cs(ym_bspal_cs)
);

wire dl_ym_snd   = ioctl_wr6 & ym_snd_cs;
wire dl_ym_grad0 = ioctl_wr6 & ym_grad0_cs;
wire dl_ym_grad1 = ioctl_wr6 & ym_grad1_cs;
wire dl_ym_pal_b = ioctl_wr6 & ym_pal_b_cs;

wire tr_bank_cs, tr_prog_cs, tr_tile0_cs, tr_tile1_cs, tr_bs0_cs, tr_bs1_cs, tr_bg0_cs, tr_bg1_cs, tr_smp_cs, tr_pal_cs;

selector_toprollr rom_sel_tr
(
    .ioctl_addr(ioctl_addr),
    .bank_cs(tr_bank_cs),
    .prog_cs(tr_prog_cs),
    .tile0_cs(tr_tile0_cs),
    .tile1_cs(tr_tile1_cs),
    .bs0_cs(tr_bs0_cs),
    .bs1_cs(tr_bs1_cs),
    .bg0_cs(tr_bg0_cs),
    .bg1_cs(tr_bg1_cs),
    .smp_cs(tr_smp_cs),
    .pal_cs(tr_pal_cs)
);

wire dl_tr_bank = ioctl_wr7 & tr_bank_cs;
wire dl_tr_pal  = ioctl_wr7 & tr_pal_cs;

wire dl_prog   = (ioctl_wr0 & prog_cs) | (ioctl_wr2 & sw_prog_cs) | (ioctl_wr5 & tq_prog_cs) | (ioctl_wr6 & ym_prog_cs) |
                 (ioctl_wr7 & tr_prog_cs);
wire dl_himem  = ioctl_wr2 & sw_himem_cs;
wire dl_snd    = ioctl_wr2 & sw_snd_cs;
wire dl_tile0  = (ioctl_wr0 & tile0_cs) | (ioctl_wr2 & sw_tile_cs[0]) | (ioctl_wr5 & tq_tile0_cs) | (ioctl_wr6 & ym_tile0_cs) |
                 (ioctl_wr7 & tr_tile0_cs);
wire dl_tile1  = (ioctl_wr0 & tile1_cs) | (ioctl_wr2 & sw_tile_cs[1]) | (ioctl_wr5 & tq_tile1_cs) | (ioctl_wr6 & ym_tile1_cs) |
                 (ioctl_wr7 & tr_tile1_cs);
wire dl_tile2  = ioctl_wr2 & sw_tile_cs[2];
wire dl_bs0    = (ioctl_wr0 & bs0_cs) | (ioctl_wr2 & sw_bs_cs[0]) | (ioctl_wr5 & tq_bs0_cs) | (ioctl_wr6 & ym_bs0_cs) |
                 (ioctl_wr7 & tr_bs0_cs);
wire dl_bs1    = (ioctl_wr0 & bs1_cs) | (ioctl_wr2 & sw_bs_cs[1]) | (ioctl_wr5 & tq_bs1_cs) | (ioctl_wr6 & ym_bs1_cs) |
                 (ioctl_wr7 & tr_bs1_cs);
wire dl_bs2    = ioctl_wr2 & sw_bs_cs[2];
wire dl_smp    = (ioctl_wr0 & smp_cs) | (ioctl_wr7 & tr_smp_cs);
wire dl_pal    = (ioctl_wr0 & pal_cs) | (ioctl_wr5 & tq_pal_cs) | (ioctl_wr6 & ym_pal_rg_cs);
wire dl_pal_lo = ioctl_wr2 & sw_pal_lo_cs;
wire dl_pal_hi = ioctl_wr2 & sw_pal_hi_cs;
wire dl_bspal  = (ioctl_wr0 & bspal_cs) | (ioctl_wr2 & sw_bspal_cs) | (ioctl_wr5 & tq_bspal_cs) | (ioctl_wr6 & ym_bspal_cs);
wire dl_dprom  = ioctl_wr0 & dprom_cs;
wire dl_sprom  = ioctl_wr0 & sprom_cs;
wire dl_spch   = ioctl_wr0 & spch_cs;

// Plane RAM addresses: tile slots are 8K on both indexes, big sprite planes 2K (index 0) / 4K (index 2)
wire [12:0] dl_tile_addr = ioctl_addr[12:0];
wire [12:0] dl_bs_addr   = ioctl_wr7 ? ioctl_addr[12:0] :
                           (ioctl_wr2 | ioctl_wr5 | ioctl_wr6) ? {1'b0, ioctl_addr[11:0]} : {2'b00, ioctl_addr[10:0]};

/////////////////////////////  Shared CPU / sound chip pool  /////////////////////////////

// Only one board family runs at a time (selected by swimmer / tangramq / yamato), so the CPUs, AYs and the TMS5110 are
// instanced once here and the board drives them (rtl/chip_pool_pkg.sv). Pool chips take the core reset.

chip_pool_pkg::z80_i_t         z80_0_i, z80_1_i;
chip_pool_pkg::z80_o_t         z80_0_o, z80_1_o;
chip_pool_pkg::aysel_i_t [1:0] aysel_i;
chip_pool_pkg::aysel_o_t [1:0] aysel_o;
chip_pool_pkg::tms5110_i_t     tms_i;
chip_pool_pkg::tms5110_o_t     tms_o;

// z80_0: main CPU, every board
T80s #(.Mode(0), .T2Write(1), .IOWait(1)) z80_0
(
    .RESET_n(~reset), .CLK(clk), .CEN(z80_0_i.ce), .WAIT_n(1'b1), .INT_n(z80_0_i.int_n), .NMI_n(z80_0_i.nmi_n), .BUSRQ_n(1'b1),
    .M1_n(z80_0_o.m1_n), .MREQ_n(z80_0_o.mreq_n), .IORQ_n(z80_0_o.iorq_n), .RD_n(z80_0_o.rd_n), .WR_n(z80_0_o.wr_n),
    .RFSH_n(z80_0_o.rfsh_n), .HALT_n(), .BUSAK_n(), .OUT0(1'b0), .A(z80_0_o.a), .DI(z80_0_i.di), .DO(z80_0_o.dout)
);

// z80_1: sound CPU, Swimmer board (Swimmer, Guzzler, Au), Tangram Q, Yamato
T80s #(.Mode(0), .T2Write(1), .IOWait(1)) z80_1
(
    .RESET_n(~reset), .CLK(clk), .CEN(z80_1_i.ce), .WAIT_n(1'b1), .INT_n(z80_1_i.int_n), .NMI_n(z80_1_i.nmi_n), .BUSRQ_n(1'b1),
    .M1_n(z80_1_o.m1_n), .MREQ_n(z80_1_o.mreq_n), .IORQ_n(z80_1_o.iorq_n), .RD_n(z80_1_o.rd_n), .WR_n(z80_1_o.wr_n),
    .RFSH_n(z80_1_o.rfsh_n), .HALT_n(), .BUSAK_n(), .OUT0(1'b0), .A(z80_1_o.a), .DI(z80_1_i.di), .DO(z80_1_o.dout)
);

// AY-3-8910 x 2: aysel 0 = CC sound board (Crazy Climber, Crazy Kong, River Patrol, Cannon Ball, Top Roller, Le Bagnard)
// or AY1 of the Swimmer / Tangram Q / Yamato sound boards; aysel 1 = their AY2
genvar ai;
generate
    for (ai = 0; ai < 2; ai = ai + 1) begin : g_aysel
        jt49_bus #(.COMP(3'b010)) aysel
        (
            .rst_n(~reset), .clk(clk), .clk_en(aysel_i[ai].ce), .bdir(aysel_i[ai].bdir), .bc1(aysel_i[ai].bc1),
            .din(aysel_i[ai].din), .sel(aysel_i[ai].sel), .dout(aysel_o[ai].dout), .sound(), .A(aysel_o[ai].a),
            .B(aysel_o[ai].b), .C(aysel_o[ai].c), .sample(), .IOA_in(8'h00), .IOA_out(aysel_o[ai].ioa_out),
            .IOB_in(8'h00), .IOB_out(aysel_o[ai].iob_out)
        );
    end
endgenerate

// TMS5110 (Le Bagnard speech daughterboard)
tms5110 tms_0
(
    .clk(clk), .reset(tms_i.reset), .ce_sample(tms_i.ce_sample), .ctl(tms_i.ctl), .pdc(tms_i.pdc), .m0(tms_o.m0),
    .data_bit(tms_i.data_bit), .busy(tms_o.busy), .talk_status(tms_o.talk_status), .sample(tms_o.sample)
);

/////////////////////////////  Shared ROM blocks  /////////////////////////////
// port A = the download (decoded by ioctl index and address above), port B = the board's read

wire [14:0] prog_a;     wire [12:0] prog_hi_a, rom0_a, tile_a, bs_a, spch_a, smp_a, tr_spr_a;
wire [15:0] tr_bank_a;  wire [11:0] grad_a, tr_bg_a;
wire  [7:0] prog_q, prog_hi_q, tr_bank_q, rom0_d, tile0_q, tile1_q, tile2_q, bs0_q, bs1_q, bs2_q, grad0_q, grad1_q;
wire  [7:0] spch_q, smp_q, tr_spr0_q, tr_spr1_q, tr_bg0_q, tr_bg1_q;

wire load_rom0 = dl_snd | dl_tq_snd | dl_ym_snd;

dpram_dc #(.widthad_a(15)) prog_rom
(
    .clock_a(clk), .address_a(ioctl_addr[14:0]), .data_a(ioctl_dout), .wren_a(dl_prog),
    .clock_b(clk), .address_b(prog_a), .q_b(prog_q)
);
dpram_dc #(.widthad_a(13)) prog_rom_hi
(
    .clock_a(clk), .address_a(ioctl_addr[12:0]), .data_a(ioctl_dout), .wren_a(dl_himem),
    .clock_b(clk), .address_b(prog_hi_a), .q_b(prog_hi_q)
);
// Top Roller: banked program, 0000-3FFF from bank {Q6,Q5}, 4000-5FFF fixed
dpram_dc #(.widthad_a(16)) tr_bank_rom
(
    .clock_a(clk), .address_a(ioctl_addr[15:0]), .data_a(ioctl_dout), .wren_a(dl_tr_bank),
    .clock_b(clk), .address_b(tr_bank_a), .q_b(tr_bank_q)
);
// rom0: sound CPU program. Swimmer board index 2 0A000-0AFFF, Tangram Q index 5 0C000-0DFFF, Yamato index 6 0E000-0E7FF
dpram_dc #(.widthad_a(13)) rom0
(
    .clock_a(clk), .address_a(ioctl_addr[12:0]), .data_a(ioctl_dout), .wren_a(load_rom0),
    .clock_b(clk), .address_b(rom0_a), .q_b(rom0_d)
);
// Plane order follows the "tile" region: first plane = pixel MSB
dpram_dc #(.widthad_a(13)) tile_rom0
(
    .clock_a(clk), .address_a(dl_tile_addr), .data_a(ioctl_dout), .wren_a(dl_tile0),
    .clock_b(clk), .address_b(tile_a), .q_b(tile0_q)
);
dpram_dc #(.widthad_a(13)) tile_rom1
(
    .clock_a(clk), .address_a(dl_tile_addr), .data_a(ioctl_dout), .wren_a(dl_tile1),
    .clock_b(clk), .address_b(tile_a), .q_b(tile1_q)
);
dpram_dc #(.widthad_a(13)) tile_rom2
(
    .clock_a(clk), .address_a(dl_tile_addr), .data_a(ioctl_dout), .wren_a(dl_tile2),
    .clock_b(clk), .address_b(tile_a), .q_b(tile2_q)
);
dpram_dc #(.widthad_a(13)) bs_rom0
(
    .clock_a(clk), .address_a(dl_bs_addr), .data_a(ioctl_dout), .wren_a(dl_bs0),
    .clock_b(clk), .address_b(bs_a), .q_b(bs0_q)
);
dpram_dc #(.widthad_a(13)) bs_rom1
(
    .clock_a(clk), .address_a(dl_bs_addr), .data_a(ioctl_dout), .wren_a(dl_bs1),
    .clock_b(clk), .address_b(bs_a), .q_b(bs1_q)
);
dpram_dc #(.widthad_a(13)) bs_rom2
(
    .clock_a(clk), .address_a(dl_bs_addr), .data_a(ioctl_dout), .wren_a(dl_bs2),
    .clock_b(clk), .address_b(bs_a), .q_b(bs2_q)
);
// Yamato gradient
dpram_dc #(.widthad_a(12)) grad0
(
    .clock_a(clk), .address_a(ioctl_addr[11:0]), .data_a(ioctl_dout), .wren_a(dl_ym_grad0),
    .clock_b(clk), .address_b(grad_a), .q_b(grad0_q)
);
dpram_dc #(.widthad_a(12)) grad1
(
    .clock_a(clk), .address_a(ioctl_addr[11:0]), .data_a(ioctl_dout), .wren_a(dl_ym_grad1),
    .clock_b(clk), .address_b(grad_a), .q_b(grad1_q)
);
// Le Bagnard speech ROMs
dpram_dc #(.widthad_a(13)) spch_rom
(
    .clock_a(clk), .address_a(ioctl_addr[12:0]), .data_a(ioctl_dout), .wren_a(dl_spch),
    .clock_b(clk), .address_b(spch_a), .q_b(spch_q)
);
// CC samples (index 0 0B000-0CFFF, Top Roller index 7: 8K aligned)
dpram_dc #(.widthad_a(13)) smp_rom
(
    .clock_a(clk), .address_a(ioctl_wr7 ? ioctl_addr[12:0] : ioctl_addr[12:0] - 13'h1000), .data_a(ioctl_dout), .wren_a(dl_smp),
    .clock_b(clk), .address_b(smp_a), .q_b(smp_q)
);
// Top Roller sprite planes (a copy of the tile planes, so the sprite engine never contends with the playfield) and
// background planes
dpram_dc #(.widthad_a(13)) tr_spr_rom0
(
    .clock_a(clk), .address_a(ioctl_addr[12:0]), .data_a(ioctl_dout), .wren_a(ioctl_wr7 & tr_tile0_cs),
    .clock_b(clk), .address_b(tr_spr_a), .q_b(tr_spr0_q)
);
dpram_dc #(.widthad_a(13)) tr_spr_rom1
(
    .clock_a(clk), .address_a(ioctl_addr[12:0]), .data_a(ioctl_dout), .wren_a(ioctl_wr7 & tr_tile1_cs),
    .clock_b(clk), .address_b(tr_spr_a), .q_b(tr_spr1_q)
);
dpram_dc #(.widthad_a(12)) tr_bg_rom0
(
    .clock_a(clk), .address_a(ioctl_addr[11:0]), .data_a(ioctl_dout), .wren_a(ioctl_wr7 & tr_bg0_cs),
    .clock_b(clk), .address_b(tr_bg_a), .q_b(tr_bg0_q)
);
dpram_dc #(.widthad_a(12)) tr_bg_rom1
(
    .clock_a(clk), .address_a(ioctl_addr[11:0]), .data_a(ioctl_dout), .wren_a(ioctl_wr7 & tr_bg1_cs),
    .clock_b(clk), .address_b(tr_bg_a), .q_b(tr_bg1_q)
);

/////////////////////////////  Board RAM pool  /////////////////////////////
// dual-port (dpram_dc)                         single-port (spram, port A of pram_i_t)
//   pr 0  4K   work RAM 6000 / C000 (+ hiscore)   sp 0  1K   colour RAM (scroll, sprites, attributes)
//   pr 1  2K   RAM 8000 (+ hiscore)               sp 1  256  sprite line buffer
//   pr 2  1K   tile RAM 9000 (+ hiscore)          sp 2  256  big sprite RAM
//   pr 3  256  Top Roller sprite RAM              sp 3  1K   sound board RAM (Swimmer / Tangram Q / Yamato)
//   pr 4  1K   Top Roller bg video RAM
//   pr 5  1K   Top Roller bg colour RAM
//   pr 6  512  Top Roller sprite line buffer
// The single-port blocks stay spram (write-through read), as the private RAMs they replace.

ram_pool_pkg::pram_i_t [6:0] pr_i;
ram_pool_pkg::pram_o_t [6:0] pr_o;
ram_pool_pkg::pram_i_t [3:0] sp_i;
ram_pool_pkg::pram_o_t [3:0] sp_o;

dpram_dc #(.widthad_a(12)) pr_0
(
    .clock_a(clk), .wren_a(pr_i[0].a_we), .address_a(pr_i[0].a_addr[11:0]), .data_a(pr_i[0].a_d), .q_a(pr_o[0].a_q),
    .clock_b(clk), .wren_b(pr_i[0].b_we), .address_b(pr_i[0].b_addr[11:0]), .data_b(pr_i[0].b_d), .q_b(pr_o[0].b_q)
);
dpram_dc #(.widthad_a(11)) pr_1
(
    .clock_a(clk), .wren_a(pr_i[1].a_we), .address_a(pr_i[1].a_addr[10:0]), .data_a(pr_i[1].a_d), .q_a(pr_o[1].a_q),
    .clock_b(clk), .wren_b(pr_i[1].b_we), .address_b(pr_i[1].b_addr[10:0]), .data_b(pr_i[1].b_d), .q_b(pr_o[1].b_q)
);
dpram_dc #(.widthad_a(10)) pr_2
(
    .clock_a(clk), .wren_a(pr_i[2].a_we), .address_a(pr_i[2].a_addr[9:0]), .data_a(pr_i[2].a_d), .q_a(pr_o[2].a_q),
    .clock_b(clk), .wren_b(pr_i[2].b_we), .address_b(pr_i[2].b_addr[9:0]), .data_b(pr_i[2].b_d), .q_b(pr_o[2].b_q)
);
dpram_dc #(.widthad_a(8)) pr_3
(
    .clock_a(clk), .wren_a(pr_i[3].a_we), .address_a(pr_i[3].a_addr[7:0]), .data_a(pr_i[3].a_d), .q_a(pr_o[3].a_q),
    .clock_b(clk), .wren_b(pr_i[3].b_we), .address_b(pr_i[3].b_addr[7:0]), .data_b(pr_i[3].b_d), .q_b(pr_o[3].b_q)
);
dpram_dc #(.widthad_a(10)) pr_4
(
    .clock_a(clk), .wren_a(pr_i[4].a_we), .address_a(pr_i[4].a_addr[9:0]), .data_a(pr_i[4].a_d), .q_a(pr_o[4].a_q),
    .clock_b(clk), .wren_b(pr_i[4].b_we), .address_b(pr_i[4].b_addr[9:0]), .data_b(pr_i[4].b_d), .q_b(pr_o[4].b_q)
);
dpram_dc #(.widthad_a(10)) pr_5
(
    .clock_a(clk), .wren_a(pr_i[5].a_we), .address_a(pr_i[5].a_addr[9:0]), .data_a(pr_i[5].a_d), .q_a(pr_o[5].a_q),
    .clock_b(clk), .wren_b(pr_i[5].b_we), .address_b(pr_i[5].b_addr[9:0]), .data_b(pr_i[5].b_d), .q_b(pr_o[5].b_q)
);
dpram_dc #(.widthad_a(9)) pr_6
(
    .clock_a(clk), .wren_a(pr_i[6].a_we), .address_a(pr_i[6].a_addr[8:0]), .data_a(pr_i[6].a_d), .q_a(pr_o[6].a_q),
    .clock_b(clk), .wren_b(pr_i[6].b_we), .address_b(pr_i[6].b_addr[8:0]), .data_b(pr_i[6].b_d), .q_b(pr_o[6].b_q)
);

spram #(.DATA_WIDTH(8), .ADDR_WIDTH(10)) sp_0
(
    .clk(clk), .addr(sp_i[0].a_addr[9:0]), .data(sp_i[0].a_d), .q(sp_o[0].a_q), .we(sp_i[0].a_we)
);
assign sp_o[0].b_q = 8'd0;
spram #(.DATA_WIDTH(8), .ADDR_WIDTH(8)) sp_1
(
    .clk(clk), .addr(sp_i[1].a_addr[7:0]), .data(sp_i[1].a_d), .q(sp_o[1].a_q), .we(sp_i[1].a_we)
);
assign sp_o[1].b_q = 8'd0;
spram #(.DATA_WIDTH(8), .ADDR_WIDTH(8)) sp_2
(
    .clk(clk), .addr(sp_i[2].a_addr[7:0]), .data(sp_i[2].a_d), .q(sp_o[2].a_q), .we(sp_i[2].a_we)
);
assign sp_o[2].b_q = 8'd0;
spram #(.DATA_WIDTH(8), .ADDR_WIDTH(10)) sp_3
(
    .clk(clk), .addr(sp_i[3].a_addr[9:0]), .data(sp_i[3].a_d), .q(sp_o[3].a_q), .we(sp_i[3].a_we)
);
assign sp_o[3].b_q = 8'd0;

/////////////////////////////  Board  /////////////////////////////

cclimber_main board
(
    .clk(clk), .reset(reset), .ce12(ce12), .pause(pause),
    .swimmer(swimmer), .au(au), .cannonb(cannonb), .cb_xor(cb_xor), .tangramq(tangramq), .yamato(yamato),
    .toprollr(toprollr), .bagmanf(bagmanf), .decrypt_en(decrypt_en), .rom_xor(rom_xor), .vol5_en(vol5_en), .nmi_q3(nmi_q3),
    .in_p1(in_p1), .in_p2(in_p2), .in_dsw(in_dsw), .in_sys(in_sys), .in_sys1(in_sys1), .in_sys2(in_sys2),
    .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
    .video_r(video_r), .video_g(video_g), .video_b(video_b), .video_hs(video_hs), .video_vs(video_vs),
    .video_hblank(video_hblank), .video_vblank(video_vblank), .ce_pix(ce_pix),
    .crt_flip(crt_flip), .h_adj(h_adj), .v_adj(v_adj), .flip_x(flip_x), .flip_y(flip_y),
    .audio(audio),
    .hs_address(hs_address), .hs_data_in(hs_data_in), .hs_data_out(hs_data_out), .hs_write(hs_write),
    .dl_dprom(dl_dprom), .dl_pal(dl_pal), .dl_pal_lo(dl_pal_lo), .dl_pal_hi(dl_pal_hi), .dl_bspal(dl_bspal),
    .dl_tr_pal(dl_tr_pal), .dl_ym_pal_b(dl_ym_pal_b), .dl_sprom(dl_sprom),
    .z80_0_i(z80_0_i), .z80_0_o(z80_0_o), .z80_1_i(z80_1_i), .z80_1_o(z80_1_o), .aysel_i(aysel_i), .aysel_o(aysel_o),
    .tms_i(tms_i), .tms_o(tms_o),
    .prog_a(prog_a), .prog_q(prog_q), .prog_hi_a(prog_hi_a), .prog_hi_q(prog_hi_q), .tr_bank_a(tr_bank_a), .tr_bank_q(tr_bank_q),
    .rom0_a(rom0_a), .rom0_d(rom0_d), .tile_a(tile_a), .tile0_q(tile0_q), .tile1_q(tile1_q), .tile2_q(tile2_q),
    .bs_a(bs_a), .bs0_q(bs0_q), .bs1_q(bs1_q), .bs2_q(bs2_q), .grad_a(grad_a), .grad0_q(grad0_q), .grad1_q(grad1_q),
    .spch_a(spch_a), .spch_q(spch_q), .smp_a(smp_a), .smp_q(smp_q),
    .tr_spr_a(tr_spr_a), .tr_spr0_q(tr_spr0_q), .tr_spr1_q(tr_spr1_q), .tr_bg_a(tr_bg_a), .tr_bg0_q(tr_bg0_q), .tr_bg1_q(tr_bg1_q),
    .pr_i(pr_i), .pr_o(pr_o), .sp_i(sp_i), .sp_o(sp_o)
);

endmodule
