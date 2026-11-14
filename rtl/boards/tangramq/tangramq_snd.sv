//  Based on MAME cclimber.cpp, snkwave.cpp (Nicola Salmoria, BSD-3-Clause)
//  Copyright (C) 2026 Rodimus

module tangramq_snd
(
    input               clk,
    input               reset,
    input               pause,

    input               latch_we,
    input         [7:0] latch_din,

    output       [12:0] rom0_a,
    input         [7:0] rom0_d,

    output chip_pool_pkg::z80_i_t   z80_1_i,
    input  chip_pool_pkg::z80_o_t   z80_1_o,
    output chip_pool_pkg::aysel_i_t [1:0] aysel_i,
    input  chip_pool_pkg::aysel_o_t [1:0] aysel_o,

    output signed [15:0] audio,

    output ram_pool_pkg::pram_i_t pr_i,
    input  ram_pool_pkg::pram_o_t pr_o
);

reg [9:0] frac = 10'd0;
reg       cen_8m = 1'b0;
always_ff @(posedge clk) begin
    if (frac >= 10'd643) begin
        frac   <= frac - 10'd643;
        cen_8m <= 1'b1;
    end else begin
        frac   <= frac + 10'd125;
        cen_8m <= 1'b0;
    end
end

reg ph = 1'b0;
always_ff @(posedge clk) if (cen_8m) ph <= ~ph;
wire cen_4m = cen_8m & ph;

reg [13:0] nmi_div = 14'd0;
always_ff @(posedge clk) if (cen_4m) nmi_div <= nmi_div + 14'd1;
wire nmi_tick = cen_4m && (nmi_div == 14'h3FFF);

wire [15:0] addr;
wire  [7:0] cpu_do;
reg   [7:0] cpu_di;
wire        m1_n, mreq_n, iorq_n, rd_n, wr_n;
reg         nmi_n = 1'b1;
reg         int_n = 1'b1;

assign z80_1_i.ce    = cen_4m & ~pause;
assign z80_1_i.int_n = int_n;
assign z80_1_i.nmi_n = nmi_n;
assign z80_1_i.di    = cpu_di;
assign addr   = z80_1_o.a;
assign cpu_do = z80_1_o.dout;
assign m1_n   = z80_1_o.m1_n;
assign mreq_n = z80_1_o.mreq_n;
assign iorq_n = z80_1_o.iorq_n;
assign rd_n   = z80_1_o.rd_n;
assign wr_n   = z80_1_o.wr_n;

wire mem_rd   = ~mreq_n & ~rd_n;
wire mem_wr   = ~mreq_n & ~wr_n;
wire rom_cs   = addr[15:13] == 3'b000;
wire latch_cs = addr[15:13] == 3'b010;
wire snd_cs   = addr[15:13] == 3'b100;
wire nmic_cs  = addr[15:13] == 3'b101;
wire ram_cs   = addr[15:13] == 3'b111;
wire int_ack  = ~m1_n & ~iorq_n;

wire [7:0] rom_do, ram_do;

assign rom0_a = addr[12:0];
assign rom_do = rom0_d;

assign pr_i.a_addr = 16'(addr[9:0]);
assign pr_i.a_d    = cpu_do;
assign pr_i.a_we   = mem_wr & ram_cs;
assign pr_i.b_addr = 16'(15'd0);
assign pr_i.b_d    = 8'd0;
assign pr_i.b_we   = 1'b0;
assign ram_do = pr_o.a_q;

reg [7:0] latch = 8'h00;
always_ff @(posedge clk) begin
    if (reset) begin
        latch <= 8'h00;
        int_n <= 1'b1;
    end else if (latch_we) begin
        latch <= latch_din;
        int_n <= 1'b0;
    end else if (int_ack | (mem_rd & latch_cs))
        int_n <= 1'b1;
end

always_ff @(posedge clk) begin
    if (reset)
        nmi_n <= 1'b1;
    else if (mem_wr & nmic_cs)
        nmi_n <= 1'b1;
    else if (nmi_tick)
        nmi_n <= 1'b0;
end

always_comb begin
    if (rom_cs)        cpu_di = rom_do;
    else if (ram_cs)   cpu_di = ram_do;
    else if (latch_cs) cpu_di = latch;
    else               cpu_di = 8'hFF;
end

wire ay1_sel = mem_wr & snd_cs & (addr[3:1] == 3'b000);
wire ay2_sel = mem_wr & snd_cs & (addr[3:1] == 3'b100);

wire [7:0] a1, b1, c1, a2, b2, c2;

assign aysel_i[0].ce   = cen_4m;
assign aysel_i[0].sel  = 1'b0;
assign aysel_i[0].bdir = ay1_sel;
assign aysel_i[0].bc1  = ay1_sel & ~addr[0];
assign aysel_i[0].din  = cpu_do;
assign a1 = aysel_o[0].a;
assign b1 = aysel_o[0].b;
assign c1 = aysel_o[0].c;

assign aysel_i[1].ce   = cen_4m;
assign aysel_i[1].sel  = 1'b0;
assign aysel_i[1].bdir = ay2_sel;
assign aysel_i[1].bc1  = ay2_sel & ~addr[0];
assign aysel_i[1].din  = cpu_do;
assign a2 = aysel_o[1].a;
assign b2 = aysel_o[1].b;
assign c2 = aysel_o[1].c;

reg [11:0] wave_freq = 12'hFFF;
reg  [2:0] wave_nib [8];
reg [11:0] wave_cnt = 12'd0;
reg  [3:0] wave_pos = 4'd0;

wire wave_we = mem_wr & snd_cs & (addr[3:0] >= 4'd2) & (addr[3:0] <= 4'd7);
reg  wave_we_d = 1'b0;

always_ff @(posedge clk) begin
    wave_we_d <= wave_we;
    if (wave_we & ~wave_we_d) begin
        if (addr[3:0] == 4'd2)
            wave_freq[11:6] <= cpu_do[7:2];
        else if (addr[3:0] == 4'd3)
            wave_freq[5:0]  <= cpu_do[5:0];
        else begin
            wave_nib[{addr[1:0], 1'b0}]        <= cpu_do[6:4];
            wave_nib[{addr[1:0], 1'b0} + 3'd1] <= cpu_do[2:0];
        end
    end

    if (cen_8m) begin
        if (wave_cnt == 12'hFFF) begin
            wave_cnt <= wave_freq;
            wave_pos <= wave_pos + 4'd1;
        end else
            wave_cnt <= wave_cnt + 12'd1;
    end
end

wire [3:0] wave_dac = (wave_freq == 12'hFFF) ? 4'd8 :
                      wave_pos[3] ? (4'd7 - {1'b0, wave_nib[~wave_pos[2:0]]}) : (4'd8 + {1'b0, wave_nib[wave_pos[2:0]]});

wire [10:0] ay_sum = {3'b000, a1} + {3'b000, b1} + {3'b000, c1} + {3'b000, a2} + {3'b000, b2} + {3'b000, c2};
wire [15:0] mix    = {2'b00, ay_sum, 3'b000} + (wave_dac * 16'd117);

jt49_dcrm2 #(.sw(16)) dcrm
(
    .clk(clk),
    .cen(nmi_div[4:0] == 5'd0 && cen_4m),
    .rst(reset),
    .din(mix),
    .dout(audio)
);

endmodule
