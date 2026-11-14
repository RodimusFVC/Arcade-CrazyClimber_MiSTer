//  Based on MAME cclimber.cpp (Nicola Salmoria, BSD-3-Clause)
//  Copyright (C) 2026 Rodimus
// Video timing and scanout pipeline from Crazy Climber FPGA by Dar (darfpga@aol.fr, http://darfpga.blogspot.fr)

module cclimber_dispatcher
(
    input               clk,
    input               reset,
    input               ce12,
    input               pause,

    input               swimmer,
    input               au,
    input               cannonb,
    input               cb_xor,
    input               tangramq,
    input               yamato,
    input               toprollr,
    input               bagmanf,
    input               decrypt_en,
    input         [1:0] rom_xor,
    input               vol5_en,
    input               nmi_q3,

    input         [7:0] in_p1,
    input         [7:0] in_p2,
    input         [7:0] in_dsw,
    input         [7:0] in_sys,
    input         [7:0] in_sys1,
    input         [7:0] in_sys2,

    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               ioctl_wr0,
    input               ioctl_wr2,
    input               ioctl_wr5,
    input               ioctl_wr6,
    input               ioctl_wr7,

    output        [7:0] video_r,
    output        [7:0] video_g,
    output        [7:0] video_b,
    output              video_hs,
    output              video_vs,
    output              video_hblank,
    output              video_vblank,
    output              ce_pix,

    input               crt_flip,
    input  signed [3:0] h_adj,
    input  signed [3:0] v_adj,

    output              flip_x,
    output              flip_y,

    output signed [15:0] audio,

    input        [15:0] hs_address,
    input         [7:0] hs_data_in,
    output        [7:0] hs_data_out,
    input               hs_write
);

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

wire [12:0] dl_tile_addr = ioctl_addr[12:0];
wire [12:0] dl_bs_addr   = ioctl_wr7 ? ioctl_addr[12:0] :
                           (ioctl_wr2 | ioctl_wr5 | ioctl_wr6) ? {1'b0, ioctl_addr[11:0]} : {2'b00, ioctl_addr[10:0]};

/////////////////////////////  Shared CPU / sound chip pool  /////////////////////////////

chip_pool_pkg::z80_i_t         z80_0_i, z80_1_i;
chip_pool_pkg::z80_o_t         z80_0_o, z80_1_o;
chip_pool_pkg::aysel_i_t [1:0] aysel_i;
chip_pool_pkg::aysel_o_t [1:0] aysel_o;
chip_pool_pkg::tms5110_i_t     tms_i;
chip_pool_pkg::tms5110_o_t     tms_o;

// z80_0: main CPU, every board
t80sv_T80s #(.Mode(0), .T2Write(1), .IOWait(1)) z80_0
(
    .RESET_n(~reset), .CLK(clk), .CEN(z80_0_i.ce), .WAIT_n(1'b1), .INT_n(z80_0_i.int_n), .NMI_n(z80_0_i.nmi_n), .BUSRQ_n(1'b1),
    .M1_n(z80_0_o.m1_n), .MREQ_n(z80_0_o.mreq_n), .IORQ_n(z80_0_o.iorq_n), .RD_n(z80_0_o.rd_n), .WR_n(z80_0_o.wr_n),
    .RFSH_n(z80_0_o.rfsh_n), .HALT_n(), .BUSAK_n(), .OUT0(1'b0), .A(z80_0_o.a), .DI(z80_0_i.di), .DO(z80_0_o.dout)
);

// z80_1: sound CPU, Swimmer board (Swimmer, Guzzler, Au), Tangram Q, Yamato
t80sv_T80s #(.Mode(0), .T2Write(1), .IOWait(1)) z80_1
(
    .RESET_n(~reset), .CLK(clk), .CEN(z80_1_i.ce), .WAIT_n(1'b1), .INT_n(z80_1_i.int_n), .NMI_n(z80_1_i.nmi_n), .BUSRQ_n(1'b1),
    .M1_n(z80_1_o.m1_n), .MREQ_n(z80_1_o.mreq_n), .IORQ_n(z80_1_o.iorq_n), .RD_n(z80_1_o.rd_n), .WR_n(z80_1_o.wr_n),
    .RFSH_n(z80_1_o.rfsh_n), .HALT_n(), .BUSAK_n(), .OUT0(1'b0), .A(z80_1_o.a), .DI(z80_1_i.di), .DO(z80_1_o.dout)
);

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

tms5110 tms_0
(
    .clk(clk), .reset(tms_i.reset), .ce_sample(tms_i.ce_sample), .ctl(tms_i.ctl), .pdc(tms_i.pdc), .m0(tms_o.m0),
    .data_bit(tms_i.data_bit), .busy(tms_o.busy), .talk_status(tms_o.talk_status), .sample(tms_o.sample)
);

chip_pool_pkg::sega_315_5018_i_t sega_315_5018_0_i;
chip_pool_pkg::sega_315_5018_o_t sega_315_5018_0_o;
sega_315_5018 sega_315_5018_0
(
    .src(sega_315_5018_0_i.src), .addr(sega_315_5018_0_i.addr), .m1(sega_315_5018_0_i.m1), .dout(sega_315_5018_0_o.dout)
);

chip_pool_pkg::tmsprom_i_t tmsprom_0_i;
chip_pool_pkg::tmsprom_o_t tmsprom_0_o;
wire [12:0] spch_a;
wire  [7:0] spch_q;
tmsprom tmsprom_0
(
    .clk(clk), .reset(reset | ~bagmanf | tmsprom_0_i.reset), .ce_romclk(tmsprom_0_i.ce_romclk),
    .chip_busy(tmsprom_0_i.chip_busy), .enable(tmsprom_0_i.enable), .bit_sel(tmsprom_0_i.bit_sel),
    .csq0(tmsprom_0_i.csq0), .csq1(tmsprom_0_i.csq1),
    .prom_wr(tmsprom_0_i.prom_wr), .prom_waddr(tmsprom_0_i.prom_waddr), .prom_wdata(tmsprom_0_i.prom_wdata),
    .rom_addr(spch_a), .rom_q(spch_q),
    .m0(tmsprom_0_i.m0), .data_bit(tmsprom_0_o.data_bit), .ctl(tmsprom_0_o.ctl), .pdc(tmsprom_0_o.pdc)
);

/////////////////////////////  Shared ROM blocks  /////////////////////////////

wire [14:0] prog_a;     wire [12:0] prog_hi_a, rom0_a, tile_a, bs_a, smp_a, tr_spr_a;
wire [15:0] tr_bank_a;  wire [11:0] grad_a, tr_bg_a;
wire  [7:0] prog_q, prog_hi_q, tr_bank_q, rom0_d, tile0_q, tile1_q, tile2_q, bs0_q, bs1_q, bs2_q, grad0_q, grad1_q;
wire  [7:0] smp_q, tr_spr0_q, tr_spr1_q, tr_bg0_q, tr_bg1_q;

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
dpram_dc #(.widthad_a(16)) tr_bank_rom
(
    .clock_a(clk), .address_a(ioctl_addr[15:0]), .data_a(ioctl_dout), .wren_a(dl_tr_bank),
    .clock_b(clk), .address_b(tr_bank_a), .q_b(tr_bank_q)
);
dpram_dc #(.widthad_a(13)) rom0
(
    .clock_a(clk), .address_a(ioctl_addr[12:0]), .data_a(ioctl_dout), .wren_a(load_rom0),
    .clock_b(clk), .address_b(rom0_a), .q_b(rom0_d)
);
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
dpram_dc #(.widthad_a(13)) spch_rom
(
    .clock_a(clk), .address_a(ioctl_addr[12:0]), .data_a(ioctl_dout), .wren_a(dl_spch),
    .clock_b(clk), .address_b(spch_a), .q_b(spch_q)
);
dpram_dc #(.widthad_a(13)) smp_rom
(
    .clock_a(clk), .address_a(ioctl_wr7 ? ioctl_addr[12:0] : ioctl_addr[12:0] - 13'h1000), .data_a(ioctl_dout), .wren_a(dl_smp),
    .clock_b(clk), .address_b(smp_a), .q_b(smp_q)
);
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
//   pr 0  4K   work RAM 6000 / C000 (+ hiscore)   sp 0  1K   colour RAM (scroll, sprites, attributes)
//   pr 1  2K   RAM 8000 (+ hiscore)               sp 1  256  sprite line buffer
//   pr 2  1K   tile RAM 9000 (+ hiscore)          sp 2  256  big sprite RAM
//   pr 3  256  Top Roller sprite RAM              sp 3  1K   sound board RAM (Swimmer / Tangram Q / Yamato)
//   pr 4  1K   Top Roller bg video RAM
//   pr 5  1K   Top Roller bg colour RAM
//   pr 6  512  Top Roller sprite line buffer

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

dpram_dc #(.widthad_a(10)) sp_0
(
    .clock_a(clk), .address_a(sp_i[0].a_addr[9:0]), .data_a(sp_i[0].a_d), .wren_a(sp_i[0].a_we), .q_a(sp_o[0].a_q),
    .clock_b(clk)
);
assign sp_o[0].b_q = 8'd0;
dpram_dc #(.widthad_a(8)) sp_1
(
    .clock_a(clk), .address_a(sp_i[1].a_addr[7:0]), .data_a(sp_i[1].a_d), .wren_a(sp_i[1].a_we), .q_a(sp_o[1].a_q),
    .clock_b(clk)
);
assign sp_o[1].b_q = 8'd0;
dpram_dc #(.widthad_a(8)) sp_2
(
    .clock_a(clk), .address_a(sp_i[2].a_addr[7:0]), .data_a(sp_i[2].a_d), .wren_a(sp_i[2].a_we), .q_a(sp_o[2].a_q),
    .clock_b(clk)
);
assign sp_o[2].b_q = 8'd0;
dpram_dc #(.widthad_a(10)) sp_3
(
    .clock_a(clk), .address_a(sp_i[3].a_addr[9:0]), .data_a(sp_i[3].a_d), .wren_a(sp_i[3].a_we), .q_a(sp_o[3].a_q),
    .clock_b(clk)
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
    .sega_315_5018_0_i(sega_315_5018_0_i), .sega_315_5018_0_o(sega_315_5018_0_o),
    .tmsprom_0_i(tmsprom_0_i), .tmsprom_0_o(tmsprom_0_o),
    .prog_a(prog_a), .prog_q(prog_q), .prog_hi_a(prog_hi_a), .prog_hi_q(prog_hi_q), .tr_bank_a(tr_bank_a), .tr_bank_q(tr_bank_q),
    .rom0_a(rom0_a), .rom0_d(rom0_d), .tile_a(tile_a), .tile0_q(tile0_q), .tile1_q(tile1_q), .tile2_q(tile2_q),
    .bs_a(bs_a), .bs0_q(bs0_q), .bs1_q(bs1_q), .bs2_q(bs2_q), .grad_a(grad_a), .grad0_q(grad0_q), .grad1_q(grad1_q),
    .smp_a(smp_a), .smp_q(smp_q),
    .tr_spr_a(tr_spr_a), .tr_spr0_q(tr_spr0_q), .tr_spr1_q(tr_spr1_q), .tr_bg_a(tr_bg_a), .tr_bg0_q(tr_bg0_q), .tr_bg1_q(tr_bg1_q),
    .pr_i(pr_i), .pr_o(pr_o), .sp_i(sp_i), .sp_o(sp_o)
);

endmodule
