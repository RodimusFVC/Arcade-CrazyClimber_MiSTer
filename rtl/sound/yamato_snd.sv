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

    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               rom_wr,         // ioctl index 6, 0E000-0E7FF

    output signed [15:0] audio
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

T80s #(.Mode(0), .T2Write(1), .IOWait(1)) z80
(
    .RESET_n(~reset),
    .CLK(clk),
    .CEN(cen & ~pause),
    .WAIT_n(1'b1),
    .INT_n(1'b1),
    .NMI_n(1'b1),
    .BUSRQ_n(1'b1),
    .M1_n(m1_n),
    .MREQ_n(mreq_n),
    .IORQ_n(iorq_n),
    .RD_n(rd_n),
    .WR_n(wr_n),
    .RFSH_n(),
    .HALT_n(),
    .BUSAK_n(),
    .OUT0(1'b0),
    .A(addr),
    .DI(cpu_di),
    .DO(cpu_do)
);

// 0000-07FF ROM, 5000-53FF RAM
wire mem_wr = ~mreq_n & ~wr_n;
wire rom_cs = addr[15:11] == 5'b00000;
wire ram_cs = addr[15:10] == 6'b010100;

wire [7:0] rom_do, ram_do;

dpram_dc #(.widthad_a(11)) rom
(
    .clock_a(clk),
    .address_a(ioctl_addr[10:0]),
    .data_a(ioctl_dout),
    .wren_a(rom_wr),

    .clock_b(clk),
    .address_b(addr[10:0]),
    .q_b(rom_do)
);

spram #(.DATA_WIDTH(8), .ADDR_WIDTH(10)) ram
(
    .clk(clk),
    .addr(addr[9:0]),
    .data(cpu_do),
    .q(ram_do),
    .we(mem_wr & ram_cs)
);

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

jt49_bus #(.COMP(3'b010)) ay1
(
    .rst_n(~reset),
    .clk(clk),
    .clk_en(cen),
    .bdir(ay1_sel),
    .bc1(ay1_sel & ~addr[0]),
    .din(cpu_do),
    .sel(1'b1),
    .dout(),
    .sound(),
    .A(a1),
    .B(b1),
    .C(c1),
    .sample(),
    .IOA_in(8'h00),
    .IOA_out(),
    .IOB_in(8'h00),
    .IOB_out()
);

jt49_bus #(.COMP(3'b010)) ay2
(
    .rst_n(~reset),
    .clk(clk),
    .clk_en(cen),
    .bdir(ay2_sel),
    .bc1(ay2_sel & ~addr[0]),
    .din(cpu_do),
    .sel(1'b1),
    .dout(),
    .sound(),
    .A(a2),
    .B(b2),
    .C(c2),
    .sample(),
    .IOA_in(8'h00),
    .IOA_out(),
    .IOB_in(8'h00),
    .IOB_out()
);

//------------------------------------------------------- Mix -----------------------------------------------------------------//

// MAME: both AYs at 0.25
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
