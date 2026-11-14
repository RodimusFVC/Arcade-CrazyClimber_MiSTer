//  Based on MAME cclimber.cpp (Nicola Salmoria, BSD-3-Clause)
//  Copyright (C) 2026 Rodimus
// Video timing and scanout pipeline from Crazy Climber FPGA by Dar (darfpga@aol.fr, http://darfpga.blogspot.fr)

module cclimber_main
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

    output        [7:0] video_r,
    output        [7:0] video_g,
    output        [7:0] video_b,
    output reg          video_hs = 1'b1,
    output reg          video_vs = 1'b1,
    output reg          video_hblank = 1'b1,
    output reg          video_vblank = 1'b1,
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
    input               hs_write,

    input               dl_dprom, dl_pal, dl_pal_lo, dl_pal_hi, dl_bspal, dl_tr_pal, dl_ym_pal_b, dl_sprom,

    output chip_pool_pkg::z80_i_t         z80_0_i,
    input  chip_pool_pkg::z80_o_t         z80_0_o,
    output chip_pool_pkg::z80_i_t         z80_1_i,
    input  chip_pool_pkg::z80_o_t         z80_1_o,
    output chip_pool_pkg::aysel_i_t [1:0] aysel_i,
    input  chip_pool_pkg::aysel_o_t [1:0] aysel_o,
    output chip_pool_pkg::tms5110_i_t     tms_i,
    input  chip_pool_pkg::tms5110_o_t     tms_o,
    output chip_pool_pkg::sega_315_5018_i_t sega_315_5018_0_i,
    input  chip_pool_pkg::sega_315_5018_o_t sega_315_5018_0_o,
    output chip_pool_pkg::tmsprom_i_t     tmsprom_0_i,
    input  chip_pool_pkg::tmsprom_o_t     tmsprom_0_o,

    output       [14:0] prog_a,
    input         [7:0] prog_q,
    output       [12:0] prog_hi_a,
    input         [7:0] prog_hi_q,
    output       [15:0] tr_bank_a,
    input         [7:0] tr_bank_q,
    output       [12:0] rom0_a,
    input         [7:0] rom0_d,
    output       [12:0] tile_a,
    input         [7:0] tile0_q, tile1_q, tile2_q,
    output       [12:0] bs_a,
    input         [7:0] bs0_q, bs1_q, bs2_q,
    output       [11:0] grad_a,
    input         [7:0] grad0_q, grad1_q,
    output       [12:0] smp_a,
    input         [7:0] smp_q,
    output       [12:0] tr_spr_a,
    input         [7:0] tr_spr0_q, tr_spr1_q,
    output       [11:0] tr_bg_a,
    input         [7:0] tr_bg0_q, tr_bg1_q,

    output ram_pool_pkg::pram_i_t [6:0] pr_i,
    input  ram_pool_pkg::pram_o_t [6:0] pr_o,
    output ram_pool_pkg::pram_i_t [3:0] sp_i,
    input  ram_pool_pkg::pram_o_t [3:0] sp_o
);

reg ena_pixel = 1'b0;
always_ff @(posedge clk) if (ce12) ena_pixel <= ~ena_pixel;

wire ce_px = ce12 & ena_pixel;
assign ce_pix = ce_px;

reg [8:0] hcnt   = 9'd511;
reg [8:0] vcnt   = 9'd511;
reg [8:0] vcnt_r = 9'd511;

wire [8:0] hs_on    = 9'd175 + {{4{h_adj[3]}}, h_adj, 1'b0};
wire [8:0] v_line   = vcnt - 9'd248;
wire [8:0] vs_start = v_adj[3] ? 9'd263 + {{5{1'b1}}, v_adj} : v_adj == 4'sd0 ? 9'd263 : {5'd0, v_adj} - 9'd1;
wire [9:0] vs_dist  = v_line >= vs_start ? {1'b0, v_line - vs_start} : {1'b0, v_line} + 10'd264 - {1'b0, vs_start};

always_ff @(posedge clk) begin
    if (ce_px) begin
        if (hcnt == 9'd511) begin
            hcnt   <= 9'd128;
            vcnt_r <= vcnt;
        end else
            hcnt <= hcnt + 9'd1;

        if (hcnt == 9'd175)
            vcnt <= (vcnt == 9'd511) ? 9'd248 : vcnt + 9'd1;

        if (hcnt == hs_on)               video_hs <= 1'b0;
        else if (hcnt == hs_on + 9'd29)  video_hs <= 1'b1;

        video_vs <= vs_dist >= 10'd3;

        if (hcnt == 9'd137) video_hblank <= 1'b1;
        else if (hcnt == 9'd264) begin
            video_hblank <= 1'b0;
            if (vcnt == 9'd497)      video_vblank <= 1'b1;
            else if (vcnt == 9'd273) video_vblank <= 1'b0;
        end
    end
end

wire       is_sprite = ~hcnt[8];
wire [2:0] sprite    = hcnt[6:4];
wire [4:0] x_tile    = hcnt[7:3];
wire [2:0] x_pixel   = hcnt[2:0];
wire [4:0] y_tile    = vcnt_r[7:3];
wire [2:0] y_pixel   = vcnt_r[2:0];

wire       hinv      = flip_x ^ crt_flip;
wire       vinv      = flip_y ^ crt_flip;
wire [7:0] y_line    = vcnt_r[7:0] ^ {8{vinv}};
wire [4:0] x_tile_v  = x_tile ^ {5{hinv}};

reg [7:0] mainlatch = 8'h00;
assign flip_x = mainlatch[1];
assign flip_y = cannonb ? mainlatch[1] : mainlatch[2];
wire   sidebg_en  = swimmer & ~au & mainlatch[3];
wire   pal_bank   = swimmer & ~au & mainlatch[4];

wire cpu_rise = ce_px &  hcnt[0];
wire cpu_fall = ce_px & ~hcnt[0];

wire [15:0] cpu_addr;
wire  [7:0] cpu_do;
reg   [7:0] cpu_di;
wire        cpu_m1_n, cpu_mreq_n, cpu_iorq_n, cpu_rd_n, cpu_wr_n;
reg         cpu_nmi_n = 1'b1;
reg         cpu_int_n = 1'b1;

assign z80_0_i.ce    = cpu_rise & ~pause;
assign z80_0_i.int_n = cpu_int_n;
assign z80_0_i.nmi_n = cpu_nmi_n;
assign z80_0_i.di    = cpu_di;

assign cpu_addr   = z80_0_o.a;
assign cpu_do     = z80_0_o.dout;
assign cpu_m1_n   = z80_0_o.m1_n;
assign cpu_mreq_n = z80_0_o.mreq_n;
assign cpu_iorq_n = z80_0_o.iorq_n;
assign cpu_rd_n   = z80_0_o.rd_n;
assign cpu_wr_n   = z80_0_o.wr_n;

chip_pool_pkg::z80_i_t sw_z80_1_i, tq_z80_1_i, ym_z80_1_i;
assign z80_1_i = swimmer ? sw_z80_1_i : tangramq ? tq_z80_1_i : ym_z80_1_i;

chip_pool_pkg::aysel_i_t [0:0] cc_aysel_i;
chip_pool_pkg::aysel_i_t [1:0] sw_aysel_i, tq_aysel_i, ym_aysel_i;
assign aysel_i[0] = swimmer ? sw_aysel_i[0] : tangramq ? tq_aysel_i[0] : yamato ? ym_aysel_i[0] : cc_aysel_i[0];
assign aysel_i[1] = swimmer ? sw_aysel_i[1] : tangramq ? tq_aysel_i[1] : ym_aysel_i[1];

wire [12:0] sw_r0a, tq_r0a, ym_r0a;
assign rom0_a = swimmer ? sw_r0a : tangramq ? tq_r0a : ym_r0a;

wire       mem_wr   = ~cpu_mreq_n & ~cpu_wr_n;
wire [4:0] a_hi     = cpu_addr[15:11];

wire rom_cs   = toprollr ? ((cpu_addr < 16'h6000) | (cpu_addr[15:14] == 2'b11)) :
                swimmer ? (~cpu_addr[15] | (cpu_addr[15:13] == 3'b111)) :
                yamato  ? ((cpu_addr < 16'h6000) | (cpu_addr[15:12] == 4'h7)) : (cpu_addr < 16'h6000);
wire ram6_cs  = cpu_addr[15:12] == (swimmer ? 4'hC : 4'h6);
wire ram8_cs  = a_hi == 5'b10000;
wire bsram_cs = swimmer ? (a_hi == 5'b10001) : (cpu_addr[15:8] == 8'h88);
wire tile_cs  = a_hi == 5'b10010;
wire color_cs = a_hi == 5'b10011;

wire latch_we = mem_wr & (a_hi == 5'b10100);
wire a800_we  = mem_wr & (a_hi == 5'b10101);
wire b000_we  = mem_wr & (a_hi == 5'b10110);
wire b800_we  = mem_wr & (a_hi == 5'b10111);

wire [7:0] rom_lo_do, rom_hi_do;

assign prog_a    = toprollr ? {1'b0, cpu_addr[13:0]} : cpu_addr[14:0];
assign rom_lo_do = prog_q;

assign prog_hi_a = cpu_addr[12:0];
assign rom_hi_do = prog_hi_q;

wire [7:0]  tr_bank_do;
wire [15:0] tr_bank_addr = {(cpu_addr[14] ? 2'b11 : {mainlatch[6], mainlatch[5]}), cpu_addr[13:0]};

assign tr_bank_a  = tr_bank_addr;
assign tr_bank_do = tr_bank_q;

wire tr_banked = toprollr & (cpu_addr < 16'h6000);
wire [7:0] rom_do = tr_banked ? tr_bank_do : toprollr ? rom_lo_do : cpu_addr[15] ? rom_hi_do : rom_lo_do;

reg [7:0] rom_xor_mask;
always_comb begin
    rom_xor_mask = 8'h00;
    case (rom_xor)
        2'd1: if (cpu_addr < 16'h5000) rom_xor_mask = cpu_addr[0] ? 8'h5B : 8'h79;
        2'd2: rom_xor_mask = 8'hF0;
        2'd3: if (cpu_addr < 16'h5000 &&
                  ((cpu_addr[11:0] >= 12'h500 && cpu_addr[11:0] < 12'h800) || cpu_addr[11:0] >= 12'hD00))
                  rom_xor_mask = 8'hFF;
        default: ;
    endcase
    if (cb_xor && cpu_addr < 16'h1000)
        case ({cpu_addr[9], cpu_addr[7]})
            2'd0: rom_xor_mask = 8'h92;
            2'd1: rom_xor_mask = 8'h82;
            2'd2: rom_xor_mask = 8'h12;
            2'd3: rom_xor_mask = 8'h10;
        endcase
end

wire [7:0] rom_src = rom_do ^ rom_xor_mask;

reg  [3:0] dprom [256];
always_ff @(posedge clk) if (dl_dprom) dprom[ioctl_addr[7:0]] <= ioctl_dout[3:0];

wire [7:0] dp_idx = {1'b0, cpu_addr[0], rom_src[7], rom_src[1], rom_src[4], rom_src[6], rom_src[2], rom_src[0]};
wire [3:0] dp     = dprom[dp_idx];
wire [7:0] rom_dec = (rom_src & 8'hAA) | {1'b0, dp[2], 1'b0, dp[3], 1'b0, dp[1], 1'b0, dp[0]};

wire [7:0] rom_5018;
assign sega_315_5018_0_i.src  = rom_src;
assign sega_315_5018_0_i.addr = cpu_addr;
assign sega_315_5018_0_i.m1   = ~cpu_m1_n;
assign rom_5018 = sega_315_5018_0_o.dout;

wire [7:0] rom_data = (yamato | tr_banked) ? rom_5018 : (decrypt_en & ~cpu_m1_n) ? rom_dec : rom_src;

wire [7:0] ram6_do, ram8_do;

wire       hs_ram6 = hs_address[15:12] == 4'h6 || hs_address[15:12] == 4'hC;
wire       hs_ram8 = hs_address[15:11] == 5'b10000;
wire       hs_tile = hs_address[15:11] == 5'b10010;
reg  [1:0] hs_sel = 2'd0;
wire [7:0] hs_ram6_do, hs_ram8_do, hs_tile_do;
always_ff @(posedge clk) hs_sel <= hs_ram6 ? 2'd0 : hs_ram8 ? 2'd1 : 2'd2;
assign hs_data_out = (hs_sel == 2'd0) ? hs_ram6_do : (hs_sel == 2'd1) ? hs_ram8_do : hs_tile_do;

ram_pool_pkg::pram_i_t ram6_i;
assign ram6_i.a_addr = 16'(cpu_addr[11:0]);
assign ram6_i.a_d    = cpu_do;
assign ram6_i.a_we   = mem_wr & ram6_cs;
assign ram6_i.b_addr = 16'(hs_address[11:0]);
assign ram6_i.b_d    = hs_data_in;
assign ram6_i.b_we   = hs_write & hs_ram6;
assign ram6_do = pr_o[0].a_q;
assign hs_ram6_do = pr_o[0].b_q;

ram_pool_pkg::pram_i_t ram8_i;
assign ram8_i.a_addr = 16'({swimmer & cpu_addr[10], cpu_addr[9:0]});
assign ram8_i.a_d    = cpu_do;
assign ram8_i.a_we   = mem_wr & ram8_cs & ~tangramq;
assign ram8_i.b_addr = 16'({swimmer & hs_address[10], hs_address[9:0]});
assign ram8_i.b_d    = hs_data_in;
assign ram8_i.b_we   = hs_write & hs_ram8 & ~tangramq;
assign ram8_do = pr_o[1].a_q;
assign hs_ram8_do = pr_o[1].b_q;

wire [7:0] ay_dout;
wire [7:0] bs_ram_do, tile_ram_do, color_ram_do;
wire [7:0] tr_cpu_di;
wire       tr_cpu_sel;

always_comb begin
    if (~cpu_iorq_n)
        cpu_di = (~cpu_m1_n | swimmer | yamato) ? 8'hFF : ay_dout;
    else if (toprollr && tr_cpu_sel)
        cpu_di = tr_cpu_di;
    else if (rom_cs)
        cpu_di = rom_data;
    else if (ram6_cs)
        cpu_di = ram6_do;
    else case (a_hi)
        5'b10000: cpu_di = bagmanf ? in_p1 : tangramq ? (cpu_addr[5] ? in_sys2 : in_sys1) : ram8_do;
        5'b10001: cpu_di = (bagmanf && cpu_addr[10:0] == 11'd0) ? in_p2 :
                           cannonb ? 8'h00 : bs_ram_do;
        5'b10010: cpu_di = tile_ram_do;
        5'b10011: cpu_di = (bagmanf && cpu_addr[10:0] == 11'd0) ? in_sys : color_ram_do;
        5'b10100: cpu_di = bagmanf ? 8'h3F : in_p1;
        5'b10101: cpu_di = bagmanf ? 8'hFF : in_p2;
        5'b10110: cpu_di = in_dsw;
        5'b10111: cpu_di = bagmanf ? 8'hFF : in_sys;
        default:  cpu_di = 8'h00;
    endcase
end

reg nmi_en = 1'b0;

always_ff @(posedge clk) begin
    if (reset) begin
        mainlatch <= 8'h00;
        nmi_en    <= 1'b0;
    end else if (cpu_fall && latch_we) begin
        mainlatch[cpu_addr[2:0]] <= cpu_do[0];
        if (cpu_addr[2:0] == 3'd0 || (nmi_q3 && cpu_addr[2:0] == 3'd3))
            nmi_en <= cpu_do[0];
    end
end

wire vbl_line = y_tile == 5'b11100 && y_pixel == 3'b000;
always_ff @(posedge clk) begin
    if (!nmi_en)
        cpu_nmi_n <= 1'b1;
    else if (ce12 && vbl_line && !bagmanf)
        cpu_nmi_n <= 1'b0;
end

reg vbl_line_d = 1'b0;
always_ff @(posedge clk) begin
    if (ce12) vbl_line_d <= vbl_line;
    if (reset)
        cpu_int_n <= 1'b1;
    else if (~cpu_m1_n & ~cpu_iorq_n)
        cpu_int_n <= 1'b1;
    else if (ce12 && vbl_line && !vbl_line_d && nmi_en && bagmanf)
        cpu_int_n <= 1'b0;
end

reg       bs_prio = 1'b0;
reg [5:0] attr_big_sprite = 6'd0;
reg [7:0] y_big_sprite = 8'd0;
reg [7:0] x_big_sprite = 8'd0;

wire bs_ctrl_cs = cpu_addr[15:2] == (swimmer ? 14'h263F : toprollr ? 14'h2677 : 14'h2637);

always_ff @(posedge clk) begin
    if (ce12 && mem_wr && bs_ctrl_cs) begin
        case (cpu_addr[1:0])
            2'd0: bs_prio         <= cpu_do[0];
            2'd1: attr_big_sprite <= cpu_do[5:0];
            2'd2: y_big_sprite    <= cpu_do;
            2'd3: x_big_sprite    <= cpu_do;
        endcase
    end
end

reg [7:0] bgcolor = 8'd0;
always_ff @(posedge clk) if (ce12 && b800_we && swimmer && !au) bgcolor <= cpu_do;

reg [7:0] aupal_b  [64];
reg [7:0] aupal_gr [64];
always_ff @(posedge clk) begin
    if (ce12 && b800_we && au) begin
        if (cpu_addr[0]) aupal_gr[cpu_addr[6:1]] <= cpu_do;
        else             aupal_b[cpu_addr[6:1]]  <= cpu_do;
    end
end

wire [9:0] cpu_addr_mod = bagmanf ? cpu_addr[9:0] : {cpu_addr[10:6], cpu_addr[4:0]};
wire [4:0] spr_base     = bagmanf ? 5'b00000 : 5'b00010;
reg  [7:0] attr_cc = 8'd0;

wire [7:0] y_line_shift;

reg  [9:0] color_ram_addr = 10'd0;
reg        color_ram_we = 1'b0;
reg  [7:0] y_sp_bg = 8'd0, attr_sp_bg = 8'd0, attr_sp = 8'd0, x_sprite = 8'd0;

always_ff @(posedge clk) begin
    if (ce12) begin
        color_ram_we <= 1'b0;
        case (x_pixel)
            3'b000: begin
                color_ram_addr <= is_sprite ? {spr_base, sprite, 2'b10} : {5'b00000, x_tile_v};
                if (ena_pixel) y_sp_bg <= ((toprollr | bagmanf) & ~is_sprite) ? 8'd0 : color_ram_do;
            end
            3'b010: begin
                color_ram_addr <= is_sprite ? {spr_base, sprite, 2'b01} :
                                  bagmanf   ? {y_line_shift[7:3], x_tile_v} : {1'b1, y_line_shift[7:4], x_tile_v};
                if (ena_pixel) attr_sp_bg <= color_ram_do;
            end
            3'b100: begin
                color_ram_addr <= is_sprite ? {spr_base, sprite, 2'b00} :
                                  {y_line_shift[7:4], y_line_shift[3] ^ attr_sp_bg[7], x_tile_v};
                if (ena_pixel) begin
                    attr_sp <= color_ram_do;
                    if (~is_sprite) attr_cc <= color_ram_do;
                end
            end
            3'b110: begin
                color_ram_addr <= is_sprite ? {spr_base, sprite, 2'b11} : 10'd0;
                if (ena_pixel) x_sprite <= color_ram_do;
            end
            default: begin
                color_ram_addr <= cpu_addr_mod;
                color_ram_we   <= mem_wr & color_cs & ~(bagmanf & cpu_addr[10]);
            end
        endcase
    end
end

ram_pool_pkg::pram_i_t colr_i;
assign colr_i.a_addr = 16'(color_ram_addr);
assign colr_i.a_d    = cpu_do;
assign colr_i.a_we   = color_ram_we;
assign colr_i.b_addr = 16'(15'd0);
assign colr_i.b_d    = 8'd0;
assign colr_i.b_we   = 1'b0;
assign color_ram_do = sp_o[0].a_q;

reg [9:0] tile_ram_addr = 10'd0;
reg       tile_ram_we = 1'b0;

always_ff @(posedge clk) begin
    if (ce12) begin
        tile_ram_we <= 1'b0;
        if (x_pixel == 3'b100)
            tile_ram_addr <= {y_line_shift[7:4], y_line_shift[3] ^ (attr_sp_bg[7] & ~toprollr), x_tile_v};
        else begin
            tile_ram_addr <= cpu_addr[9:0];
            tile_ram_we   <= mem_wr & tile_cs & ~(toprollr & cpu_addr[10]);
        end
    end
end

ram_pool_pkg::pram_i_t tram_i;
assign tram_i.a_addr = 16'(tile_ram_addr);
assign tram_i.a_d    = cpu_do;
assign tram_i.a_we   = tile_ram_we;
assign tram_i.b_addr = 16'(hs_address[9:0]);
assign tram_i.b_d    = hs_data_in;
assign tram_i.b_we   = hs_write & hs_tile;
assign tile_ram_do = pr_o[2].a_q;
assign hs_tile_do = pr_o[2].b_q;

assign y_line_shift = y_line + y_sp_bg + 8'd1;

reg  [12:0] tile_graph_rom_addr = 13'd0;
reg   [7:0] bg_tile_code = 8'd0;
reg   [4:0] tile_color_r = 5'd0;
reg   [7:0] tile_graph1_r = 8'd0, tile_graph2_r = 8'd0, tile_graph3_r = 8'd0;
reg         is_sprite_r = 1'b0;
reg         keep_sprite = 1'b0;
wire  [7:0] tile_rom0_do, tile_rom1_do, tile_rom2_do;

function automatic [7:0] bitrev8(input [7:0] d);
    bitrev8 = {d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7]};
endfunction

reg [4:0] sp_row_xor;
always_comb begin
    case (attr_sp[7:6])
        2'b00:   sp_row_xor = 5'b00000;
        2'b01:   sp_row_xor = 5'b01000;
        2'b10:   sp_row_xor = 5'b10111;
        default: sp_row_xor = 5'b11111;
    endcase
end

wire [7:0] attr_cd = (bagmanf & ~is_sprite) ? attr_cc : attr_sp_bg;
wire [1:0] code_hi = au      ? {attr_sp_bg[5], attr_sp_bg[4]} :
                     swimmer ? {1'b0, attr_sp_bg[4]} :
                     cannonb ? (is_sprite ? 2'b10 : {1'b0, attr_sp_bg[5]}) : {attr_cd[4], attr_cd[5]};

always_ff @(posedge clk) begin
    if (ce12) begin
        case (x_pixel)
            3'b100: if (ena_pixel) bg_tile_code <= tile_ram_do;

            3'b110: begin
                if (is_sprite)
                    tile_graph_rom_addr <= {code_hi, attr_sp[5:0],
                                            {y_line_shift[3], x_tile[0], y_line_shift[2:0]} ^ sp_row_xor};
                else
                    tile_graph_rom_addr <= {code_hi, bg_tile_code,
                                            (attr_sp_bg[7] & ~toprollr) ? ~y_line_shift[2:0] : y_line_shift[2:0]};
            end

            3'b111: if (ena_pixel) begin
                tile_color_r <= {pal_bank, attr_cd[3:0]};
                if ((is_sprite & attr_sp[6]) | (~is_sprite & attr_sp_bg[6] & ~toprollr)) begin
                    tile_graph1_r <= bitrev8(tile_rom0_do);
                    tile_graph2_r <= bitrev8(tile_rom1_do);
                    tile_graph3_r <= bitrev8(tile_rom2_do);
                end else begin
                    tile_graph1_r <= tile_rom0_do;
                    tile_graph2_r <= tile_rom1_do;
                    tile_graph3_r <= tile_rom2_do;
                end
                is_sprite_r <= is_sprite;
                keep_sprite <= (y_line_shift[7:4] == 4'b1111) && (x_sprite != 8'h00) && (y_sp_bg != 8'h00) && !toprollr;
            end

            default: ;
        endcase
    end
end

assign tile_a = tile_graph_rom_addr;
assign tile_rom0_do = tile0_q;

assign tile_rom1_do = tile1_q;

assign tile_rom2_do = tile2_q;

wire [2:0] x_sel = (hinv & ~is_sprite_r) ? x_pixel : ~x_pixel;
wire [7:0] pixel_color = swimmer ? {tile_color_r, tile_graph1_r[x_sel], tile_graph2_r[x_sel], tile_graph3_r[x_sel]}
                                 : {2'b00, tile_color_r[3:0], tile_graph1_r[x_sel], tile_graph2_r[x_sel]};

function automatic pix_on(input sw, input [7:0] p);
    pix_on = sw ? (p[2:0] != 3'd0) : (p[1:0] != 2'd0);
endfunction

reg  [8:0] addr_ram_sprite = 9'd0;

wire [8:0] sprite_crt_adj = crt_flip ? 9'd2 : 9'd0;
wire [8:0] sprite_x_load = {1'b0, x_sprite ^ {8{hinv}}} - {8'd0, swimmer | yamato} + sprite_crt_adj;

always_ff @(posedge clk) begin
    if (ce12) begin
        if (ena_pixel)
            addr_ram_sprite <= (hinv & is_sprite_r) ? addr_ram_sprite - 9'd1 : addr_ram_sprite + 9'd1;
        if (is_sprite && x_pixel == 3'b111 && ena_pixel && !x_tile[0])
            addr_ram_sprite <= sprite_x_load;
        if (!is_sprite && x_pixel == 3'b111 && ena_pixel && x_tile == 5'd0)
            addr_ram_sprite <= 9'd1;
    end
end

wire [7:0] sprite_pixel_color;
wire       sprite_hit   = pix_on(swimmer, sprite_pixel_color);
wire [7:0] sprite_wdata = is_sprite_r ? (sprite_hit ? sprite_pixel_color : pixel_color) : 8'd0;
wire       sprite_we    = ce_px & (is_sprite_r ? (keep_sprite & ~addr_ram_sprite[8]) : 1'b1);

ram_pool_pkg::pram_i_t sline_i;
assign sline_i.a_addr = 16'(addr_ram_sprite[7:0]);
assign sline_i.a_d    = sprite_wdata;
assign sline_i.a_we   = sprite_we;
assign sline_i.b_addr = 16'(15'd0);
assign sline_i.b_d    = 8'd0;
assign sline_i.b_we   = 1'b0;
assign sprite_pixel_color = sp_o[1].a_q;

reg [7:0] pixel_color_r = 8'd0;
reg       sprite_on_r = 1'b0;
reg       pf_clear_r = 1'b1;

always_ff @(posedge clk) begin
    if (ce_px) begin
        pixel_color_r <= sprite_hit ? sprite_pixel_color : pixel_color;
        sprite_on_r   <= sprite_hit;
        pf_clear_r    <= ~sprite_hit & ~pix_on(swimmer, pixel_color);
    end
end

wire [7:0] y_line_bs = y_line + y_big_sprite + 8'd1;

reg  [7:0] x_bs_cnt = 8'd0;
reg  [7:0] bs_ram_addr = 8'd0;
reg        bs_ram_we = 1'b0;
reg  [7:0] bs_tile_code = 8'd0, bs_tile_code_r = 8'd0;
reg  [7:0] bs_graph1 = 8'd0, bs_graph2 = 8'd0, bs_graph3 = 8'd0;
reg  [7:0] bs_graph1_d = 8'd0, bs_graph2_d = 8'd0, bs_graph3_d = 8'd0;

reg        bs_vis_addr = 1'b0, bs_vis_code = 1'b0, bs_vis_r = 1'b0, bs_vis_g = 1'b0;
reg  [7:0] bs_vis_d = 8'd0;
wire [7:0] bs_rom0_do, bs_rom1_do, bs_rom2_do;

localparam [7:0] BS_CRT_FLIP_X = 8'd144;
wire [7:0] x_bs_pos = crt_flip ? BS_CRT_FLIP_X - x_big_sprite : x_big_sprite;
wire bs_fx = toprollr ? hinv : attr_big_sprite[4] ^ crt_flip;
wire bs_fy = toprollr ? 1'b0 : attr_big_sprite[5];

reg [7:0] xy_big_sprite;
always_comb begin
    case ({bs_fy, bs_fx})
        2'b01:   xy_big_sprite = { y_line_bs[6:3], ~x_bs_cnt[6:3]};
        2'b11:   xy_big_sprite = {~y_line_bs[6:3], ~x_bs_cnt[6:3]};
        2'b00:   xy_big_sprite = { y_line_bs[6:3],  x_bs_cnt[6:3]};
        default: xy_big_sprite = {~y_line_bs[6:3],  x_bs_cnt[6:3]};
    endcase
end

wire [1:0]  bs_bank     = toprollr ? attr_big_sprite[4:3] : {1'b0, (swimmer | tangramq | yamato) & attr_big_sprite[3]};
wire [12:0] bs_rom_addr = {bs_bank, bs_tile_code_r, bs_fy ? ~y_line_bs[2:0] : y_line_bs[2:0]};

always_ff @(posedge clk) begin
    if (ce12) begin
        bs_ram_we <= 1'b0;
        if (x_pixel == 3'b000) begin
            bs_ram_addr <= xy_big_sprite;
            bs_vis_addr <= ~x_bs_cnt[7];
            if (ena_pixel) begin
                bs_tile_code <= bs_ram_do;
                bs_vis_code  <= bs_vis_addr;
            end
        end else begin
            bs_ram_addr <= cpu_addr[7:0];
            bs_ram_we   <= mem_wr & bsram_cs;
        end
    end
end

ram_pool_pkg::pram_i_t bsr_i;
assign bsr_i.a_addr = 16'(bs_ram_addr);
assign bsr_i.a_d    = cpu_do;
assign bsr_i.a_we   = bs_ram_we;
assign bsr_i.b_addr = 16'(15'd0);
assign bsr_i.b_d    = 8'd0;
assign bsr_i.b_we   = 1'b0;
assign bs_ram_do = sp_o[2].a_q;

always_ff @(posedge clk) begin
    if (ce12) begin
        if (ena_pixel)
            x_bs_cnt <= x_bs_cnt + 8'd1;
        if (is_sprite && sprite == 3'b110 && ena_pixel)
            x_bs_cnt <= 8'd120 + (x_bs_pos & 8'hF8);

        if (x_bs_cnt[2:0] == 3'b111 && ena_pixel) begin
            bs_tile_code_r <= bs_tile_code;
            bs_vis_r       <= bs_vis_code;
            bs_vis_g       <= bs_vis_r;
            bs_graph1      <= bs_fx ? bs_rom0_do : bitrev8(bs_rom0_do);
            bs_graph2      <= bs_fx ? bs_rom1_do : bitrev8(bs_rom1_do);
            bs_graph3      <= bs_fx ? bs_rom2_do : bitrev8(bs_rom2_do);
        end
    end
end

assign bs_a = bs_rom_addr;
assign bs_rom0_do = bs0_q;

assign bs_rom1_do = bs1_q;

assign bs_rom2_do = bs2_q;

always_ff @(posedge clk) begin
    if (ce_px) begin
        bs_graph1_d <= {bs_graph1_d[6:0], bs_graph1[x_bs_cnt[2:0]]};
        bs_graph2_d <= {bs_graph2_d[6:0], bs_graph2[x_bs_cnt[2:0]]};
        bs_graph3_d <= {bs_graph3_d[6:0], bs_graph3[x_bs_cnt[2:0]]};
        bs_vis_d    <= {bs_vis_d[6:0], bs_vis_g};
    end
end

wire [2:0] bs_sel = ~x_bs_pos[2:0];
wire [5:0] bs_pixel_color = swimmer ? {attr_big_sprite[2:0], bs_graph1_d[bs_sel], bs_graph2_d[bs_sel], bs_graph3_d[bs_sel]}
                                    : {1'b0, attr_big_sprite[2:0], bs_graph1_d[bs_sel], bs_graph2_d[bs_sel]};

reg [5:0] bs_pixel_color_r = 6'd0;
reg       bs_pixel_vis_r = 1'b0;
reg       is_big_sprite_on = 1'b0;

always_ff @(posedge clk) begin
    if (ce12) begin
        bs_pixel_color_r <= bs_pixel_color;
        bs_pixel_vis_r   <= bs_vis_d[bs_sel];
        is_big_sprite_on <= pix_on(swimmer, {2'b00, bs_pixel_color_r}) && y_line_bs[7] && bs_pixel_vis_r && !bagmanf;
    end
end

reg [7:0] pal    [64];
reg [3:0] pal_lo [256];
reg [3:0] pal_hi [256];
reg [7:0] bspal  [32];

always_ff @(posedge clk) begin
    if (dl_pal)    pal[ioctl_addr[5:0]]    <= ioctl_dout;
    if (dl_pal_lo) pal_lo[ioctl_addr[7:0]] <= ioctl_dout[3:0];
    if (dl_pal_hi) pal_hi[ioctl_addr[7:0]] <= ioctl_dout[3:0];
    if (dl_bspal)  bspal[ioctl_addr[4:0]]  <= ioctl_dout;
end

reg [7:0] pal_tr [160];
always_ff @(posedge clk) if (dl_tr_pal && ioctl_addr[7:0] < 8'hA0) pal_tr[ioctl_addr[7:0]] <= ioctl_dout;

wire [5:0] tr_spr_pen, tr_bg_pen;
wire       tr_spr_on, tr_clip;

ram_pool_pkg::pram_i_t [3:0] trv_pr_i;
toprollr_video #(.X_START(8'd0), .Y_OFS(8'd1)) tr_video
(
    .clk(clk),
    .ce_px(ce_px),
    .hblank(video_hblank),
    .line_y(vcnt_r[7:0]),
    .flip_x(hinv),
    .flip_y(vinv),

    .cpu_addr(cpu_addr),
    .cpu_do(cpu_do),
    .cpu_wr(mem_wr & toprollr),
    .cpu_di(tr_cpu_di),
    .cpu_sel(tr_cpu_sel),

    .spr_rom_a(tr_spr_a), .spr_p0(tr_spr0_q), .spr_p1(tr_spr1_q),
    .bg_rom_a(tr_bg_a), .bg_p0(tr_bg0_q), .bg_p1(tr_bg1_q),
    .pr_i(trv_pr_i), .pr_o(pr_o[6:3]),

    .spr_pen(tr_spr_pen),
    .spr_on(tr_spr_on),
    .bg_pen(tr_bg_pen),
    .in_clip(tr_clip)
);

wire tr_bs_on = pix_on(1'b0, {2'b00, bs_pixel_color_r}) && y_line_bs[7] && bs_pixel_vis_r;
reg  [7:0] tr_pen;
always_comb begin
    tr_pen = 8'h00;
    if (tr_clip) begin
        tr_pen = 8'h60 + {2'b00, tr_bg_pen};
        if (attr_big_sprite[5]) begin
            if (tr_spr_on) tr_pen = {2'b00, tr_spr_pen};
            if (tr_bs_on)  tr_pen = 8'h40 + {3'b000, bs_pixel_color_r[4:0]};
        end else begin
            if (tr_bs_on)  tr_pen = 8'h40 + {3'b000, bs_pixel_color_r[4:0]};
            if (tr_spr_on) tr_pen = {2'b00, tr_spr_pen};
        end
    end
    if (!pf_clear_r) tr_pen = {2'b00, pixel_color_r[5:0]};
end

reg [7:0] do_tr = 8'd0;
always_ff @(posedge clk) if (ce12) do_tr <= pal_tr[tr_pen];

reg [3:0] pal_b [64];
always_ff @(posedge clk) if (dl_ym_pal_b) pal_b[ioctl_addr[5:0]] <= ioctl_dout[3:0];
reg [3:0] do_pal_b = 4'd0;
always_ff @(posedge clk) if (ce12) do_pal_b <= pal_b[pixel_color_r[5:0]];

reg [7:0] do_palette = 8'd0, do_bs_palette = 8'd0;
reg [3:0] do_pal_lo = 4'd0, do_pal_hi = 4'd0;
reg [7:0] do_au_b = 8'd0, do_au_gr = 8'd0, do_aubs_b = 8'd0, do_aubs_gr = 8'd0;

wire [5:0] au_pen = pf_clear_r ? 6'd0 : pixel_color_r[5:0];

always_ff @(posedge clk) begin
    if (ce12) begin
        do_palette    <= pal[pixel_color_r[5:0]];
        do_pal_lo     <= pal_lo[pixel_color_r];
        do_pal_hi     <= pal_hi[pixel_color_r];
        do_bs_palette <= bspal[bs_pixel_color_r[4:0]];
        do_au_b       <= aupal_b[au_pen];
        do_au_gr      <= aupal_gr[au_pen];
        do_aubs_b     <= aupal_b[bs_pixel_color_r];
        do_aubs_gr    <= aupal_gr[bs_pixel_color_r];
    end
end

function automatic [7:0] cc_dac3(input [2:0] v);
    case (v)
        3'd0: cc_dac3 = 8'd0;   3'd1: cc_dac3 = 8'd33;  3'd2: cc_dac3 = 8'd71;  3'd3: cc_dac3 = 8'd104;
        3'd4: cc_dac3 = 8'd151; 3'd5: cc_dac3 = 8'd184; 3'd6: cc_dac3 = 8'd222; 3'd7: cc_dac3 = 8'd255;
    endcase
endfunction

function automatic [7:0] cc_dac2(input [1:0] v);
    case (v)
        2'd0: cc_dac2 = 8'd0; 2'd1: cc_dac2 = 8'd81; 2'd2: cc_dac2 = 8'd174; 2'd3: cc_dac2 = 8'd255;
    endcase
endfunction

function automatic [23:0] cc_rgb(input [7:0] p);
    cc_rgb = {cc_dac3(p[2:0]), cc_dac3(p[5:3]), cc_dac2(p[7:6])};
endfunction

function automatic [23:0] sw_rgb(input [7:0] p);
    sw_rgb = {p[2:0], 5'd0, p[5:3], 5'd0, p[7:6], 6'd0};
endfunction

function automatic [7:0] pal3(input [2:0] v);
    pal3 = {v, v, v[2:1]};
endfunction

function automatic [23:0] au_rgb(input [7:0] b, input [7:0] gr);
    au_rgb = {pal3(gr[2:0]), pal3(gr[6:4]), pal3(b[2:0])};
endfunction

reg  [8:0] screen_x = 9'd0;
reg        pf_clear_d = 1'b1;
always_ff @(posedge clk) begin
    if (ce12) pf_clear_d <= pf_clear_r;
    if (ce_px) screen_x <= video_hblank ? 9'd0 : screen_x + 9'd1;
end

function automatic [7:0] ym4(input [3:0] v);
    ym4 = (v[0] ? 8'h0E : 8'h00) + (v[1] ? 8'h1F : 8'h00) + (v[2] ? 8'h43 : 8'h00) + (v[3] ? 8'h8F : 8'h00);
endfunction

function automatic [7:0] ym3(input [2:0] v);
    ym3 = (v[0] ? 8'h21 : 8'h00) + (v[1] ? 8'h47 : 8'h00) + (v[2] ? 8'h97 : 8'h00);
endfunction

wire [7:0]  grad0_do, grad1_do;
wire [7:0]  grad_x    = screen_x[7:0] + 8'd8;
wire [6:0]  grad_i    = grad_x[7:1];
wire [11:0] grad_addr = {1'b0, mainlatch[3], mainlatch[5], mainlatch[6], hinv, grad_i};

assign grad_a   = grad_addr;
assign grad0_do = grad0_q;

assign grad1_do = grad1_q;

wire [4:0]  grad_r5  = grad0_do[4:0];
wire [4:0]  grad_g5  = {grad1_do[1:0], grad0_do[7:5]};
wire [5:0]  grad_b6  = grad1_do[7:2];
wire [23:0] grad_rgb = {grad_r5, grad_r5[4:2], grad_g5, grad_g5[4:2], grad_b6, grad_b6[5:4]};

wire [23:0] pf_rgb = yamato  ? {ym4(do_palette[3:0]), ym4(do_palette[7:4]), ym4(do_pal_b)} :
                     au      ? au_rgb(do_au_b, do_au_gr) :
                     swimmer ? {do_pal_lo[2:0], 5'd0, do_pal_hi[1:0], do_pal_lo[3], 5'd0, do_pal_hi[3:2], 6'd0}
                             : cc_rgb(do_palette);
wire [23:0] bs_rgb = yamato  ? {ym3(do_bs_palette[2:0]), ym3(do_bs_palette[5:3]), ym3({do_bs_palette[7:6], 1'b0})} :
                     au      ? au_rgb(do_aubs_b, do_aubs_gr) :
                     swimmer ? sw_rgb(do_bs_palette) : cc_rgb(do_bs_palette);

wire [23:0] bg_rgb   = {bgcolor[7:6], 6'd0, bgcolor[5:3], 5'd0, bgcolor[2:0], 5'd0};
wire [23:0] side_rgb = 24'h209879;

wire side_area = sidebg_en & (hinv ? (screen_x < 9'd64) : (screen_x >= 9'd192));

reg [23:0] video_mux;
always_comb begin
    if (toprollr)
        video_mux = cc_rgb(do_tr);
    else if (is_big_sprite_on && !(bs_prio && sprite_on_r))
        video_mux = bs_rgb;
    else if (yamato && pf_clear_d)
        video_mux = grad_rgb;
    else if (swimmer && !au && pf_clear_d)
        video_mux = side_area ? side_rgb : bg_rgb;
    else
        video_mux = pf_rgb;
end

reg [23:0] video_i = 24'd0;
always_ff @(posedge clk) begin
    if (ce_px)
        video_i <= video_hblank ? 24'd0 : video_mux;
end

assign {video_r, video_g, video_b} = video_i;

wire io_wr = ~cpu_iorq_n & ~cpu_wr_n & cpu_m1_n;
wire io_rd = ~cpu_iorq_n & ~cpu_rd_n & cpu_m1_n;

wire ay_bdir = ~swimmer & io_wr & (cpu_addr[7:1] == 7'b0000_100);
wire ay_bc1  = ~swimmer & ((io_wr & (cpu_addr[7:0] == 8'h08)) | (io_rd & (cpu_addr[7:0] == 8'h0C)));

wire signed [15:0] cc_audio, sw_audio;

cclimber_snd snd
(
    .clk(clk),
    .reset(reset | swimmer | tangramq | yamato),

    .ay_bdir(ay_bdir),
    .ay_bc1(ay_bc1),
    .ay_din(cpu_do),
    .ay_dout(ay_dout),

    .rate_we(ce12 & a800_we & ~swimmer & ~bagmanf),
    .vol_we(ce12 & b000_we & ~swimmer),
    .cpu_do(cpu_do),
    .trigger(mainlatch[4] & ~swimmer & ~bagmanf),
    .vol5_en(vol5_en),
    .toprollr(toprollr),

    .smp_a(smp_a),
    .smp_q(smp_q),

    .aysel_i(cc_aysel_i),
    .aysel_o(aysel_o[0:0]),

    .audio(cc_audio)
);

ram_pool_pkg::pram_i_t sw_sp_i, tq_sp_i, ym_sp_i;

reg a800_we_d = 1'b0;
always_ff @(posedge clk) a800_we_d <= a800_we;

swimmer_snd snd_sw
(
    .clk(clk),
    .reset(reset | ~swimmer),
    .pause(pause),
    .au(au),
    .vblank(video_vblank),

    .latch_we(swimmer & a800_we_d & ~a800_we),
    .latch_din(cpu_do),

    .rom0_a(sw_r0a),
    .rom0_d(rom0_d),

    .z80_1_i(sw_z80_1_i),
    .z80_1_o(z80_1_o),
    .aysel_i(sw_aysel_i),
    .aysel_o(aysel_o),
    .pr_i(sw_sp_i),
    .pr_o(sp_o[3]),

    .audio(sw_audio)
);

wire signed [15:0] tq_audio;
reg b000_we_d = 1'b0;
always_ff @(posedge clk) b000_we_d <= b000_we;

tangramq_snd snd_tq
(
    .clk(clk),
    .reset(reset | ~tangramq),
    .pause(pause),

    .latch_we(tangramq & b000_we_d & ~b000_we),
    .latch_din(cpu_do),

    .rom0_a(tq_r0a),
    .rom0_d(rom0_d),

    .z80_1_i(tq_z80_1_i),
    .z80_1_o(z80_1_o),
    .aysel_i(tq_aysel_i),
    .aysel_o(aysel_o),
    .pr_i(tq_sp_i),
    .pr_o(sp_o[3]),

    .audio(tq_audio)
);

wire signed [15:0] ym_audio;
reg io_wr_d = 1'b0;
always_ff @(posedge clk) io_wr_d <= io_wr;
wire ym_out = yamato & io_wr & ~io_wr_d;

yamato_snd snd_ym
(
    .clk(clk),
    .reset(reset | ~yamato),
    .pause(pause),

    .latch1_we(ym_out & (cpu_addr[7:0] == 8'h00)),
    .latch2_we(ym_out & (cpu_addr[7:0] == 8'h01)),
    .latch_din(cpu_do),

    .rom0_a(ym_r0a),
    .rom0_d(rom0_d),

    .z80_1_i(ym_z80_1_i),
    .z80_1_o(z80_1_o),
    .aysel_i(ym_aysel_i),
    .aysel_o(aysel_o),
    .pr_i(ym_sp_i),
    .pr_o(sp_o[3]),

    .audio(ym_audio)
);

reg [7:0] tmslatch = 8'd0;
always_ff @(posedge clk) begin
    if (reset)
        tmslatch <= 8'd0;
    else if (cpu_fall && bagmanf && a800_we)
        tmslatch[cpu_addr[2:0]] <= cpu_do[0];
end

reg  [9:0] tms_acc = 10'd0;
reg  [5:0] tms_div = 6'd0;
reg        tms_ce = 1'b0, tms_smp = 1'b0;
always_ff @(posedge clk) begin
    tms_ce  <= 1'b0;
    tms_smp <= 1'b0;
    if (tms_acc >= 10'd763) begin
        tms_acc <= tms_acc - 10'd763;
        tms_ce  <= 1'b1;
        tms_div <= (tms_div == 6'd39) ? 6'd0 : tms_div + 6'd1;
        tms_smp <= tms_div == 6'd39;
    end else
        tms_acc <= tms_acc + 10'd5;
end

wire  [3:0] tms_ctl;
wire        tms_pdc, tms_m0, tms_bit, tms_busy;
wire signed [15:0] tms_out;

assign tmsprom_0_i.reset      = reset | ~bagmanf;
assign tmsprom_0_i.ce_romclk  = tms_ce;
assign tmsprom_0_i.chip_busy  = tms_busy;
assign tmsprom_0_i.enable     = tmslatch[3];
assign tmsprom_0_i.bit_sel    = 3'd7 - {tmslatch[0], tmslatch[1], tmslatch[2]};
assign tmsprom_0_i.csq0       = tmslatch[4];
assign tmsprom_0_i.csq1       = tmslatch[5];
assign tmsprom_0_i.prom_wr    = dl_sprom;
assign tmsprom_0_i.prom_waddr = ioctl_addr[4:0];
assign tmsprom_0_i.prom_wdata = ioctl_dout;
assign tmsprom_0_i.m0         = tms_m0;
assign tms_bit = tmsprom_0_o.data_bit;
assign tms_ctl = tmsprom_0_o.ctl;
assign tms_pdc = tmsprom_0_o.pdc;

assign tms_i.reset     = reset | ~bagmanf;
assign tms_i.ce_sample = tms_smp;
assign tms_i.ctl       = tms_ctl;
assign tms_i.pdc       = tms_pdc;
assign tms_i.data_bit  = tms_bit;
assign tms_m0   = tms_o.m0;
assign tms_busy = tms_o.busy;
assign tms_out  = tms_o.sample;

wire signed [16:0] bg_sum   = cc_audio + tms_out;
wire signed [15:0] bg_audio = (bg_sum > 17'sd32767) ? 16'sd32767 : (bg_sum < -17'sd32768) ? -16'sd32768 : bg_sum[15:0];

assign audio = swimmer ? sw_audio : tangramq ? tq_audio : yamato ? ym_audio : bagmanf ? bg_audio : cc_audio;

assign pr_i = {trv_pr_i, tram_i, ram8_i, ram6_i};
assign sp_i = {swimmer ? sw_sp_i : tangramq ? tq_sp_i : ym_sp_i, bsr_i, sline_i, colr_i};

endmodule
