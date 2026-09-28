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

    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               rom_wr,         // ioctl index 2, 0A000-0AFFF

    output signed [15:0] audio
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

T80s #(.Mode(0), .T2Write(1), .IOWait(1)) z80
(
    .RESET_n(~reset),
    .CLK(clk),
    .CEN(cen_cpu & ~pause),
    .WAIT_n(1'b1),
    .INT_n(int_n),
    .NMI_n(nmi_n),
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

// 0000-0FFF ROM, 2000-23FF RAM (mirror 0C00), 3000 latch read, 4000 NMI clear
wire mem_rd   = ~mreq_n & ~rd_n;
wire mem_wr   = ~mreq_n & ~wr_n;
wire rom_cs   = addr[15:12] == 4'h0;
wire ram_cs   = addr[15:12] == 4'h2;
wire latch_cs = addr[15:12] == 4'h3;
wire nmic_cs  = addr[15:12] == 4'h4;
wire int_ack  = ~m1_n & ~iorq_n;

wire [7:0] rom_do, ram_do;

dpram_dc #(.widthad_a(12)) rom
(
    .clock_a(clk),
    .address_a(ioctl_addr[11:0]),
    .data_a(ioctl_dout),
    .wren_a(rom_wr),

    .clock_b(clk),
    .address_b(addr[11:0]),
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

jt49_bus #(.COMP(3'b010)) ay1
(
    .rst_n(~reset),
    .clk(clk),
    .clk_en(cen_cpu),
    .bdir(ay1_bdir),
    .bc1(ay_bc1 & ~addr[7]),
    .din(cpu_do),
    .sel(~au),
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
    .clk_en(cen_cpu),
    .bdir(ay2_bdir),
    .bc1(ay_bc1 & addr[7]),
    .din(cpu_do),
    .sel(~au),
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
