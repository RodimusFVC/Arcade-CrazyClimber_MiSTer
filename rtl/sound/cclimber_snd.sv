//============================================================================
//
//  Crazy Climber sound: AY-3-8910 + TTL 4-bit sample player (CCG-2)
//  Copyright (C) 2026 Rodimus
//
//  Sample sequencing per MAME cclimber_a.cpp (Nicola Salmoria, hap);
//  DAC and volume weights from the CCG-2 schematic
//
//============================================================================

module cclimber_snd
(
    input               clk,            // 49.152 MHz
    input               reset,

    input               ay_bdir,
    input               ay_bc1,
    input         [7:0] ay_din,
    output        [7:0] ay_dout,

    input               rate_we,        // $A800
    input               vol_we,         // $B000
    input         [7:0] cpu_do,
    input               trigger,        // LS259 Q4
    input               vol5_en,        // volume D4 (47K) fitted

    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               smp_wr,         // ioctl 0B000-0CFFF

    output signed [15:0] audio
);

//------------------------------------------------------- Clock enables -------------------------------------------------------//

// AY = 18.432/3/2/2 = 1.536 MHz, sample base = 768 kHz, DC filter = 48 kHz
reg [9:0] div = 10'd0;
always_ff @(posedge clk) div <= div + 10'd1;

wire cen_ay  = div[4:0] == 5'd0;
wire cen_smp = div[5:0] == 6'd0;
wire cen_dc  = div == 10'd0;

//------------------------------------------------------- AY-3-8910 -----------------------------------------------------------//

wire [7:0] ay_a, ay_b, ay_c;
wire [7:0] start_addr, loop_addr;

jt49_bus #(.COMP(3'b010)) ay
(
    .rst_n(~reset),
    .clk(clk),
    .clk_en(cen_ay),
    .bdir(ay_bdir),
    .bc1(ay_bc1),
    .din(ay_din),
    .sel(1'b1),
    .dout(ay_dout),
    .sound(),
    .A(ay_a),
    .B(ay_b),
    .C(ay_c),
    .sample(),
    .IOA_in(8'h00),
    .IOA_out(start_addr),
    .IOB_in(8'h00),
    .IOB_out(loop_addr)
);

//------------------------------------------------------- Sample player -------------------------------------------------------//

reg  [7:0] rate = 8'd0;
reg  [4:0] volume = 5'd0;

always_ff @(posedge clk) begin
    if (rate_we) rate   <= cpu_do;
    if (vol_we)  volume <= cpu_do[4:0];
end

wire [7:0] smp_data;
reg [13:0] smp_addr = 14'd0;

dpram_dc #(.widthad_a(13)) smp_rom
(
    .clock_a(clk),
    .address_a(ioctl_addr[12:0] - 13'h1000),
    .data_a(ioctl_dout),
    .wren_a(smp_wr),

    .clock_b(clk),
    .address_b(smp_addr[13:1]),
    .q_b(smp_data)
);

// Rate counter reloads from $A800 on carry: period = 256 - rate ticks of 768 kHz
reg [7:0] rate_cnt = 8'd0;
reg [3:0] nibble = 4'd0;
reg       trig_d = 1'b0;

always_ff @(posedge clk) begin
    trig_d <= trigger;

    if (cen_smp) begin
        if (rate_cnt == 8'hFF) begin
            rate_cnt <= rate;

            nibble <= smp_addr[0] ? smp_data[3:0] : smp_data[7:4];
            if (trigger)
                smp_addr <= smp_addr + 14'd1;
            if (smp_data == 8'h70)
                smp_addr <= {loop_addr, 6'd0};
        end else
            rate_cnt <= rate_cnt + 8'd1;
    end

    if (trigger && !trig_d)
        smp_addr <= {start_addr, 6'd0};
end

//------------------------------------------------------- DAC -----------------------------------------------------------------//

// 4066 switches into 100K/200K/390K/820K, referenced to the volume amp (47K/100K/200K/390K/820K)
localparam [11:0] W47K = 12'd2128, W100K = 12'd1000, W200K = 12'd500, W390K = 12'd256, W820K = 12'd122;

wire [11:0] nib_w = (nibble[3] ? W100K : 12'd0) + (nibble[2] ? W200K : 12'd0) +
                    (nibble[1] ? W390K : 12'd0) + (nibble[0] ? W820K : 12'd0);

wire [12:0] vol_w = ((volume[4] & vol5_en) ? {1'b0, W47K} : 13'd0) +
                    (volume[3] ? {1'b0, W100K} : 13'd0) + (volume[2] ? {1'b0, W200K} : 13'd0) +
                    (volume[1] ? {1'b0, W390K} : 13'd0) + (volume[0] ? {1'b0, W820K} : 13'd0);

reg [24:0] dac_prod = 25'd0;
always_ff @(posedge clk) dac_prod <= nib_w * vol_w;

//------------------------------------------------------- Mix -----------------------------------------------------------------//

// MAME mixes AY and DAC at 0.5 each; AC coupling approximated by the DC remover
wire [9:0]  ay_sum = {2'b00, ay_a} + {2'b00, ay_b} + {2'b00, ay_c};
wire [15:0] mix    = {2'b00, ay_sum, 4'd0} + {1'b0, dac_prod[23:9]};

jt49_dcrm2 #(.sw(16)) dcrm
(
    .clk(clk),
    .cen(cen_dc),
    .rst(reset),
    .din(mix),
    .dout(audio)
);

endmodule
