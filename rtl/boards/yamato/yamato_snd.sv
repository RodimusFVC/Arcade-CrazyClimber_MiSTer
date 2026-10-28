//============================================================================
//
//  Yamato sound board: Z80 + 2 x AY-3-8910, two polled sound latches
//  Copyright (C) 2026 Rodimus
//
//  Per MAME cclimber.cpp yamato_audio_map / yamato_audio_portmap (Nicola Salmoria)
//
//============================================================================

module yamato_snd
(
    input               clk,            // 49.152 MHz
    input               reset,
    input               pause,

    input               latch1_we,      // main CPU OUT ($00)
    input               latch2_we,      // main CPU OUT ($01)
    input         [7:0] latch_din,

    output       [12:0] rom0_a,         // shared sound ROM, ioctl index 6, 0E000-0E7FF (rtl/cclimber_dispatcher.sv)
    input         [7:0] rom0_d,

    output chip_pool_pkg::z80_i_t   z80_1_i,           // shared sound Z80 (rtl/cclimber_dispatcher.sv)
    input  chip_pool_pkg::z80_o_t   z80_1_o,
    output chip_pool_pkg::aysel_i_t [1:0] aysel_i,     // shared AYs (rtl/cclimber_dispatcher.sv)
    input  chip_pool_pkg::aysel_o_t [1:0] aysel_o,

    output signed [15:0] audio,

    output ram_pool_pkg::pram_i_t pr_i,         // sound RAM = pool block sp 3 (port A) in the dispatcher
    input  ram_pool_pkg::pram_o_t pr_o
);

//------------------------------------------------------- Clocks --------------------------------------------------------------//

// 12 MHz crystal / 8 = 1.5 MHz for the Z80 and both AYs. From 49.152 MHz: 125/4096
reg [11:0] frac = 12'd0;
reg        cen = 1'b0;
always_ff @(posedge clk) begin
    if (frac >= 12'd3971) begin
        frac <= frac - 12'd3971;
        cen  <= 1'b1;
    end else begin
        frac <= frac + 12'd125;
        cen  <= 1'b0;
    end
end

//------------------------------------------------------- Z80 -----------------------------------------------------------------//

wire [15:0] addr;
wire  [7:0] cpu_do;
reg   [7:0] cpu_di;
wire        m1_n, mreq_n, iorq_n, rd_n, wr_n;

// the shared Z80 (z80_1)
assign z80_1_i.ce    = cen & ~pause;
assign z80_1_i.int_n = 1'b1;
assign z80_1_i.nmi_n = 1'b1;
assign z80_1_i.di    = cpu_di;
assign addr   = z80_1_o.a;
assign cpu_do = z80_1_o.dout;
assign m1_n   = z80_1_o.m1_n;
assign mreq_n = z80_1_o.mreq_n;
assign iorq_n = z80_1_o.iorq_n;
assign rd_n   = z80_1_o.rd_n;
assign wr_n   = z80_1_o.wr_n;

// 0000-07FF ROM, 5000-53FF RAM
wire mem_wr = ~mreq_n & ~wr_n;
wire rom_cs = addr[15:11] == 5'b00000;
wire ram_cs = addr[15:10] == 6'b010100;

wire [7:0] rom_do, ram_do;

// the shared sound ROM (rom0)
assign rom0_a = {2'b00, addr[10:0]};
assign rom_do = rom0_d;

assign pr_i.a_addr = 15'(addr[9:0]);
assign pr_i.a_d    = cpu_do;
assign pr_i.a_we   = mem_wr & ram_cs;
assign pr_i.b_addr = 15'(15'd0);
assign pr_i.b_d    = 8'd0;
assign pr_i.b_we   = 1'b0;
assign ram_do = pr_o.a_q;

//------------------------------------------------------- Sound latches (polled, no interrupts) -------------------------------//

reg [7:0] latch1 = 8'h00, latch2 = 8'h00;
always_ff @(posedge clk) begin
    if (reset) begin
        latch1 <= 8'h00;
        latch2 <= 8'h00;
    end else begin
        if (latch1_we) latch1 <= latch_din;
        if (latch2_we) latch2 <= latch_din;
    end
end

// I/O: IN 04 = latch 1, IN 08 = latch 2
wire io_rd = ~iorq_n & ~rd_n & m1_n;
wire io_wr = ~iorq_n & ~wr_n & m1_n;

always_comb begin
    if (io_rd)
        cpu_di = addr[3] ? latch2 : addr[2] ? latch1 : 8'hFF;
    else if (rom_cs)
        cpu_di = rom_do;
    else if (ram_cs)
        cpu_di = ram_do;
    else
        cpu_di = 8'hFF;
end

//------------------------------------------------------- AY-3-8910 x2 --------------------------------------------------------//

// OUT 00/01 = AY1 address/data, OUT 02/03 = AY2 address/data
wire ay1_sel = io_wr & (addr[7:1] == 7'd0);
wire ay2_sel = io_wr & (addr[7:1] == 7'd1);

wire [7:0] a1, b1, c1, a2, b2, c2;

// the shared AYs (aysel 0 / 1)
assign aysel_i[0].ce   = cen;
assign aysel_i[0].sel  = 1'b1;
assign aysel_i[0].bdir = ay1_sel;
assign aysel_i[0].bc1  = ay1_sel & ~addr[0];
assign aysel_i[0].din  = cpu_do;
assign a1 = aysel_o[0].a;
assign b1 = aysel_o[0].b;
assign c1 = aysel_o[0].c;

assign aysel_i[1].ce   = cen;
assign aysel_i[1].sel  = 1'b1;
assign aysel_i[1].bdir = ay2_sel;
assign aysel_i[1].bc1  = ay2_sel & ~addr[0];
assign aysel_i[1].din  = cpu_do;
assign a2 = aysel_o[1].a;
assign b2 = aysel_o[1].b;
assign c2 = aysel_o[1].c;

//------------------------------------------------------- Mix -----------------------------------------------------------------//

// both AYs at 0.25
wire [10:0] sum = {3'b000, a1} + {3'b000, b1} + {3'b000, c1} + {3'b000, a2} + {3'b000, b2} + {3'b000, c2};

reg [4:0] dc_div = 5'd0;
always_ff @(posedge clk) if (cen) dc_div <= dc_div + 5'd1;

jt49_dcrm2 #(.sw(16)) dcrm
(
    .clk(clk),
    .cen(cen && dc_div == 5'd0),
    .rst(reset),
    .din({1'b0, sum, 4'd0}),
    .dout(audio)
);

endmodule
