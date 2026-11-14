//  Based on MAME cclimber_a.cpp (Nicola Salmoria, hap, BSD-3-Clause)
//  Copyright (C) 2026 Rodimus

module cclimber_snd
(
    input               clk,
    input               reset,

    input               ay_bdir,
    input               ay_bc1,
    input         [7:0] ay_din,
    output        [7:0] ay_dout,

    input               rate_we,
    input               vol_we,
    input         [7:0] cpu_do,
    input               trigger,
    input               vol5_en,
    input               toprollr,

    output       [12:0] smp_a,
    input         [7:0] smp_q,

    output chip_pool_pkg::aysel_i_t [0:0] aysel_i,
    input  chip_pool_pkg::aysel_o_t [0:0] aysel_o,

    output signed [15:0] audio
);

reg [9:0] div = 10'd0;
always_ff @(posedge clk) div <= div + 10'd1;

wire cen_ay_cc  = div[4:0] == 5'd0;
wire cen_smp_cc = div[5:0] == 6'd0;
wire cen_dc     = div == 10'd0;

reg [11:0] tr_frac = 12'd0;
reg        tr_cen = 1'b0;
reg  [1:0] tr_div = 2'd0;
always_ff @(posedge clk) begin
    if (tr_frac >= 12'd3971) begin
        tr_frac <= tr_frac - 12'd3971;
        tr_cen  <= 1'b1;
    end else begin
        tr_frac <= tr_frac + 12'd125;
        tr_cen  <= 1'b0;
    end
    if (tr_cen) tr_div <= tr_div + 2'd1;
end

wire cen_ay  = toprollr ? tr_cen : cen_ay_cc;
wire cen_smp = toprollr ? (tr_cen && tr_div == 2'd0) : cen_smp_cc;

wire [7:0] ay_a, ay_b, ay_c;
wire [7:0] start_addr, loop_addr;

assign aysel_i[0].ce   = cen_ay;
assign aysel_i[0].sel  = 1'b1;
assign aysel_i[0].bdir = ay_bdir;
assign aysel_i[0].bc1  = ay_bc1;
assign aysel_i[0].din  = ay_din;
assign ay_dout    = reset ? 8'h00 : aysel_o[0].dout;
assign ay_a       = aysel_o[0].a;
assign ay_b       = aysel_o[0].b;
assign ay_c       = aysel_o[0].c;
assign start_addr = aysel_o[0].ioa_out;
assign loop_addr  = aysel_o[0].iob_out;

reg  [7:0] rate = 8'd0;
reg  [4:0] volume = 5'd0;

always_ff @(posedge clk) begin
    if (rate_we) rate   <= cpu_do;
    if (vol_we)  volume <= cpu_do[4:0];
end

wire [7:0] smp_data;
reg [13:0] smp_addr = 14'd0;

assign smp_a    = smp_addr[13:1];
assign smp_data = smp_q;

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

localparam [11:0] W47K = 12'd2128, W100K = 12'd1000, W200K = 12'd500, W390K = 12'd256, W820K = 12'd122;

wire [11:0] nib_w = (nibble[3] ? W100K : 12'd0) + (nibble[2] ? W200K : 12'd0) +
                    (nibble[1] ? W390K : 12'd0) + (nibble[0] ? W820K : 12'd0);

wire [12:0] vol_w = ((volume[4] & vol5_en) ? {1'b0, W47K} : 13'd0) +
                    (volume[3] ? {1'b0, W100K} : 13'd0) + (volume[2] ? {1'b0, W200K} : 13'd0) +
                    (volume[1] ? {1'b0, W390K} : 13'd0) + (volume[0] ? {1'b0, W820K} : 13'd0);

reg [24:0] dac_prod = 25'd0;
always_ff @(posedge clk) dac_prod <= nib_w * vol_w;

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
