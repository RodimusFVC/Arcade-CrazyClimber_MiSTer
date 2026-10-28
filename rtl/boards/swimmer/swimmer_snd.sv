//============================================================================
//
//  Swimmer sound board (Centuri B102-402): Z80 + 2 x AY-3-8910
//  Copyright (C) 2026 Rodimus
//
//  Per the Swimmer service manual "Swimmer Sound" sheet and MAME cclimber.cpp
//  (Nicola Salmoria)
//
//============================================================================

module swimmer_snd
(
    input               clk,            // 49.152 MHz
    input               reset,
    input               pause,
    input               au,             // Au: 3.072 MHz CPU, AYs at half that, NMI from main vblank
    input               vblank,

    input               latch_we,       // main CPU write to $A800 (/WRS)
    input         [7:0] latch_din,

    output       [12:0] rom0_a,         // shared sound ROM, ioctl index 2, 0A000-0AFFF (rtl/cclimber_dispatcher.sv)
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

// 4 MHz crystal into a CD4020: Q1 = 2 MHz (Z80 and both AYs), Q14 = 244 Hz (NMI)
// 2 MHz from 49.152 MHz: step 125/3072
reg [11:0] frac = 12'd0;
reg        cen_2m = 1'b0;
always_ff @(posedge clk) begin
    if (frac >= 12'd2947) begin
        frac   <= frac - 12'd2947;
        cen_2m <= 1'b1;
    end else begin
        frac   <= frac + 12'd125;
        cen_2m <= 1'b0;
    end
end

reg [12:0] nmi_div = 13'd0;
always_ff @(posedge clk) if (cen_2m) nmi_div <= nmi_div + 13'd1;
wire nmi_tick = cen_2m && (nmi_div == 13'h1FFF);

// Au: 18.432 / 6 = 3.072 MHz
reg [3:0] div16 = 4'd0;
always_ff @(posedge clk) div16 <= div16 + 4'd1;
wire cen_cpu = au ? (div16 == 4'd0) : cen_2m;

reg vblank_d = 1'b0;
always_ff @(posedge clk) vblank_d <= vblank;

//------------------------------------------------------- Z80 -----------------------------------------------------------------//

wire [15:0] addr;
wire  [7:0] cpu_do;
reg   [7:0] cpu_di;
wire        m1_n, mreq_n, iorq_n, rd_n, wr_n;
reg         nmi_n = 1'b1;
reg         int_n = 1'b1;

// the shared Z80 (z80_1)
assign z80_1_i.ce    = cen_cpu & ~pause;
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

// 0000-0FFF ROM, 2000-23FF RAM (mirror 0C00), 3000 latch read, 4000 NMI clear
wire mem_rd   = ~mreq_n & ~rd_n;
wire mem_wr   = ~mreq_n & ~wr_n;
wire rom_cs   = addr[15:12] == 4'h0;
wire ram_cs   = addr[15:12] == 4'h2;
wire latch_cs = addr[15:12] == 4'h3;
wire nmic_cs  = addr[15:12] == 4'h4;
wire int_ack  = ~m1_n & ~iorq_n;

wire [7:0] rom_do, ram_do;

// the shared sound ROM (rom0)
assign rom0_a = {1'b0, addr[11:0]};
assign rom_do = rom0_d;

assign pr_i.a_addr = 15'(addr[9:0]);
assign pr_i.a_d    = cpu_do;
assign pr_i.a_we   = mem_wr & ram_cs;
assign pr_i.b_addr = 15'(15'd0);
assign pr_i.b_d    = 8'd0;
assign pr_i.b_we   = 1'b0;
assign ram_do = pr_o.a_q;

//------------------------------------------------------- Sound latch / interrupts --------------------------------------------//

// 3F '374 + 6L '74: a main CPU write raises INT (cleared by acknowledge); reading clears the latch
reg [7:0] latch = 8'h00;
reg       latch_rd_d = 1'b0;

always_ff @(posedge clk) begin
    latch_rd_d <= mem_rd & latch_cs;

    if (reset) begin
        latch <= 8'h00;
        int_n <= 1'b1;
    end else begin
        if (latch_we) begin
            latch <= latch_din;
            int_n <= 1'b0;
        end else begin
            if (int_ack)
                int_n <= 1'b1;
            if (latch_rd_d && !(mem_rd & latch_cs))
                latch <= 8'h00;
        end
    end
end

// NMI held until any 4000 access: 244 Hz timer, or on Au the main board's vblank (released at its end)
always_ff @(posedge clk) begin
    if (reset)
        nmi_n <= 1'b1;
    else if (((mem_rd | mem_wr) & nmic_cs) || (au && !vblank && vblank_d))
        nmi_n <= 1'b1;
    else if (au ? (vblank && !vblank_d) : nmi_tick)
        nmi_n <= 1'b0;
end

always_comb begin
    if (rom_cs)        cpu_di = rom_do;
    else if (ram_cs)   cpu_di = ram_do;
    else if (latch_cs) cpu_di = latch;
    else               cpu_di = 8'hFF;
end

//------------------------------------------------------- AY-3-8910 x2 --------------------------------------------------------//

// I/O: A7 selects the chip, A0 = 1 latches the register address, A0 = 0 writes data
wire io_wr = ~iorq_n & ~wr_n & m1_n;
wire ay1_bdir = io_wr & ~addr[7];
wire ay2_bdir = io_wr &  addr[7];
wire ay_bc1   = io_wr &  addr[0];

wire [7:0] a1, b1, c1, a2, b2, c2;

// the shared AYs (aysel 0 / 1)
assign aysel_i[0].ce   = cen_cpu;
assign aysel_i[0].sel  = ~au;
assign aysel_i[0].bdir = ay1_bdir;
assign aysel_i[0].bc1  = ay_bc1 & ~addr[7];
assign aysel_i[0].din  = cpu_do;
assign a1 = aysel_o[0].a;
assign b1 = aysel_o[0].b;
assign c1 = aysel_o[0].c;

assign aysel_i[1].ce   = cen_cpu;
assign aysel_i[1].sel  = ~au;
assign aysel_i[1].bdir = ay2_bdir;
assign aysel_i[1].bc1  = ay_bc1 & addr[7];
assign aysel_i[1].din  = cpu_do;
assign a2 = aysel_o[1].a;
assign b2 = aysel_o[1].b;
assign c2 = aysel_o[1].c;

//------------------------------------------------------- Mix -----------------------------------------------------------------//

// Six channels through equal 5K resistors into the M51516L amp
wire [10:0] sum = {3'b000, a1} + {3'b000, b1} + {3'b000, c1} + {3'b000, a2} + {3'b000, b2} + {3'b000, c2};

jt49_dcrm2 #(.sw(16)) dcrm
(
    .clk(clk),
    .cen(nmi_div[4:0] == 5'd0 && cen_2m),
    .rst(reset),
    .din({1'b0, sum, 4'd0}),
    .dout(audio)
);

endmodule
