//============================================================================
//
//  Tangram Q sound board (SNK A2003UP03-01): Z80 + 2 x AY-3-8910 + SNK wave
//  Copyright (C) 2026 Rodimus
//
//  Per MAME cclimber.cpp tangramq_sound_map (Nicola Salmoria) and
//  snkwave.cpp (Nicola Salmoria)
//
//============================================================================

module tangramq_snd
(
    input               clk,            // 49.152 MHz
    input               reset,
    input               pause,

    input               latch_we,       // main CPU write to $B000
    input         [7:0] latch_din,

    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               rom_wr,         // ioctl index 5, 0C000-0DFFF

    output signed [15:0] audio
);

//------------------------------------------------------- Clocks --------------------------------------------------------------//

// 8 MHz crystal: Z80 = 4 MHz, AYs = 2 MHz, SNK wave = 8 MHz. From 49.152 MHz: 8/49.152 = 125/768
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

// 244 Hz NMI: 0x4000 ticks of 4 MHz
reg [13:0] nmi_div = 14'd0;
always_ff @(posedge clk) if (cen_4m) nmi_div <= nmi_div + 14'd1;
wire nmi_tick = cen_4m && (nmi_div == 14'h3FFF);

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
    .CEN(cen_4m & ~pause),
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

// 0000-1FFF ROM, 4000 latch read, 8000-8009 AY1 / wave / AY2, A000 NMI clear, E000-E3FF RAM
wire mem_rd   = ~mreq_n & ~rd_n;
wire mem_wr   = ~mreq_n & ~wr_n;
wire rom_cs   = addr[15:13] == 3'b000;
wire latch_cs = addr[15:13] == 3'b010;
wire snd_cs   = addr[15:13] == 3'b100;
wire nmic_cs  = addr[15:13] == 3'b101;
wire ram_cs   = addr[15:13] == 3'b111;
wire int_ack  = ~m1_n & ~iorq_n;

wire [7:0] rom_do, ram_do;

dpram_dc #(.widthad_a(13)) rom
(
    .clock_a(clk),
    .address_a(ioctl_addr[12:0]),
    .data_a(ioctl_dout),
    .wren_a(rom_wr),

    .clock_b(clk),
    .address_b(addr[12:0]),
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

// Generic latch: a main CPU write raises INT (HOLD_LINE); acknowledge or reading the latch drops it
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

// 244 Hz NMI held until a write to A000
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

//------------------------------------------------------- AY-3-8910 x2 (memory mapped) ---------------------------------------//

// 8000/8008 = register address, 8001/8009 = data
wire ay1_sel = mem_wr & snd_cs & (addr[3:1] == 3'b000);
wire ay2_sel = mem_wr & snd_cs & (addr[3:1] == 3'b100);

wire [7:0] a1, b1, c1, a2, b2, c2;

jt49_bus #(.COMP(3'b010)) ay1
(
    .rst_n(~reset),
    .clk(clk),
    .clk_en(cen_4m),
    .bdir(ay1_sel),
    .bc1(ay1_sel & ~addr[0]),
    .din(cpu_do),
    .sel(1'b0),
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
    .clk_en(cen_4m),
    .bdir(ay2_sel),
    .bc1(ay2_sel & ~addr[0]),
    .din(cpu_do),
    .sel(1'b0),
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

//------------------------------------------------------- SNK wave (8002-8007) ------------------------------------------------//

// Registers 0-1: 12-bit frequency (6 bits each); 2-5: eight 3-bit waveform values (two per register).
// The 16-step waveform plays the eight values forwards as 8+n, then backwards as 7-n, into a 4-bit DAC.
reg [11:0] wave_freq = 12'hFFF;
reg  [2:0] wave_nib [8];
reg [11:0] wave_cnt = 12'd0;
reg  [3:0] wave_pos = 4'd0;

wire wave_we = mem_wr & snd_cs & (addr[3:0] >= 4'd2) & (addr[3:0] <= 4'd7);
reg  wave_we_d = 1'b0;

always_ff @(posedge clk) begin
    wave_we_d <= wave_we;
    if (wave_we & ~wave_we_d) begin
        // 8004-8007 hold waveform values 0-1, 2-3, 4-5, 6-7
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

//------------------------------------------------------- Mix -----------------------------------------------------------------//

// MAME: each AY at 0.35, the wave at 0.30
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
