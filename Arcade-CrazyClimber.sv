//============================================================================
//
//  Crazy Climber hardware for MiSTer
//  Copyright (C) 2026 Rodimus
//
//  Video pipeline derived from Crazy Climber FPGA by Dar (darfpga@aol.fr)
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.
//
//============================================================================

module emu
(
    `include "sys/emu_ports.vh"
);

wire        CLK_49M;
wire        locked;
wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire [10:0] ps2_key;
wire        ioctl_download;
wire        ioctl_wr;
wire  [7:0] ioctl_index;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire [15:0] joystick_0, joystick_1;
wire [15:0] joystick_r_analog_0;   // right analog stick: [15:8]=Y signed, [7:0]=X signed
wire [15:0] joystick_r_analog_1;   // P2 right analog stick (cocktail)
wire [21:0] gamma_bus;
wire        direct_video;
wire        video_rotated;
wire        pause_cpu;

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign FB_FORCE_BLANK = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

wire signed [15:0] audio;
assign AUDIO_L = pause_cpu ? 16'd0 : audio;
assign AUDIO_R = pause_cpu ? 16'd0 : audio;
assign AUDIO_S = 1;   // signed
assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = ioctl_download;
assign BUTTONS = 0;

///////////////////////////////////////////////////

// MRA index 1: byte 0 = control layout, byte 1 = board flags
//   layout: 0 Crazy Climber twin stick, 1 Crazy Kong, 2 River Patrol, 3 Swimmer / Guzzler
//   flags : [0] decryption PROM, [2:1] ROM XOR mode, [3] volume D4 fitted, [4] vertical (ROT270),
//           [5] latch Q3 drives the NMI mask, [6] Swimmer board (ROMs on index 2), [7] vertical is ROT90
reg [7:0] game_layout = 8'd0;
reg [7:0] game_flags  = 8'd1;

always @(posedge CLK_49M) begin
	if (ioctl_wr && ioctl_index == 8'd1) begin
		if (ioctl_addr == 25'd0) game_layout <= ioctl_dout;
		if (ioctl_addr == 25'd1) game_flags  <= ioctl_dout;
	end
end

wire game_vert = game_flags[4];
wire vert_view = game_vert & ~status[12];

wire [1:0] ar = status[14:13];

assign VIDEO_ARX = (!ar) ? (vert_view ? 12'd3 : 12'd4) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? (vert_view ? 12'd4 : 12'd3) : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"CCLIMBER;;",
	"P1,Video Options;",
	"P1ODE,Aspect Ratio,Original,Full screen,[ARC1],[ARC2];",
	"P1OC,Orientation,Vert,Horz;",
	"P1OB,HDMI Flip,Off,On;",
	"P1OM,CRT Flip,Off,On;",
	"P1OFH,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"P2,Pause Options;",
	"P2OP,Pause when OSD is open,On,Off;",
	"P2OQ,Dim video after 10s,On,Off;",
	"-;",
	"DIP;",
	"-;",
	"R0,Reset;",
	"J1,Btn 1,Btn 2,Btn 3,Btn 4,Coin,Start 1P,Start 2P,Pause;",
	"jn,A,Y,B,X,Select,Start,R,L;",
	"V,v",`BUILD_DATE
};

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(CLK_49M),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),
	.video_rotated(video_rotated),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask({direct_video}),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_index(ioctl_index),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_r_analog_0(joystick_r_analog_0),
	.joystick_r_analog_1(joystick_r_analog_1),
	.ps2_key(ps2_key)
);

////////////////////   CLOCKS   ///////////////////

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(CLK_49M),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll),
	.locked(locked)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(0),
	.mgmt_address(0),
	.mgmt_writedata(0),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

// 12.288 MHz enable: twice the 6.144 MHz pixel clock (18.432 MHz / 3)
reg [1:0] ce_div = 2'd0;
always @(posedge CLK_49M) ce_div <= ce_div + 2'd1;
wire ce12 = (ce_div == 2'd0);

// Hold the Z80 in reset until the PLL is locked and the ROM download has finished
wire reset = RESET | status[0] | buttons[1] | ioctl_download | ~locked;

///////////////////         Keyboard           //////////////////

reg kb_up = 0, kb_down = 0, kb_left = 0, kb_right = 0;
reg kb_rup = 0, kb_rdown = 0, kb_rleft = 0, kb_rright = 0;
reg kb_b1 = 0, kb_b2 = 0;
reg kb_coin1 = 0, kb_coin2 = 0, kb_start1 = 0, kb_start2 = 0, kb_pause = 0;

wire       pressed = ~ps2_key[9];
wire [7:0] code    = ps2_key[7:0];

always @(posedge CLK_49M) begin
	reg old_state;
	old_state <= ps2_key[10];
	if (old_state != ps2_key[10]) begin
		case (code)
			'h16: kb_start1 <= pressed; // 1
			'h1E: kb_start2 <= pressed; // 2
			'h2E: kb_coin1  <= pressed; // 5
			'h36: kb_coin2  <= pressed; // 6
			'h4D: kb_pause  <= pressed; // P

			'h75: kb_up     <= pressed; // up
			'h72: kb_down   <= pressed; // down
			'h6B: kb_left   <= pressed; // left
			'h74: kb_right  <= pressed; // right
			'h14: kb_b1     <= pressed; // ctrl
			'h11: kb_b2     <= pressed; // alt

			'h1D: kb_rup    <= pressed; // W
			'h1B: kb_rdown  <= pressed; // S
			'h1C: kb_rleft  <= pressed; // A
			'h23: kb_rright <= pressed; // D
		endcase
	end
end

//////////////////  Arcade Buttons/Interfaces   ///////////////////////////

// Joystick bits: 0 R, 1 L, 2 D, 3 U, 4-7 Btn 1-4, 8 Coin, 9 Start 1P, 10 Start 2P, 11 Pause
wire m_up1    = joystick_0[3] | kb_up;
wire m_down1  = joystick_0[2] | kb_down;
wire m_left1  = joystick_0[1] | kb_left;
wire m_right1 = joystick_0[0] | kb_right;
wire m_b1_1   = joystick_0[4] | kb_b1 | kb_rright;
wire m_b2_1   = joystick_0[5] | kb_b2 | kb_rleft;
wire m_b3_1   = joystick_0[6] | kb_rdown;
wire m_b4_1   = joystick_0[7] | kb_rup;

wire m_up2    = joystick_1[3];
wire m_down2  = joystick_1[2];
wire m_left2  = joystick_1[1];
wire m_right2 = joystick_1[0];
wire m_b1_2   = joystick_1[4];
wire m_b2_2   = joystick_1[5];
wire m_b3_2   = joystick_1[6];
wire m_b4_2   = joystick_1[7];

// Right analog stick drives the right hand, same thresholds as The Tower on DECO Cassette
wire signed [7:0] rx0 = joystick_r_analog_0[7:0], ry0 = joystick_r_analog_0[15:8];
wire signed [7:0] rx1 = joystick_r_analog_1[7:0], ry1 = joystick_r_analog_1[15:8];
wire [3:0] rstick0 = {ry0 > 8'sd48, ry0 < -8'sd48, rx0 < -8'sd48, rx0 > 8'sd48};  // {D,U,L,R}
wire [3:0] rstick1 = {ry1 > 8'sd48, ry1 < -8'sd48, rx1 < -8'sd48, rx1 > 8'sd48};

wire m_coin1  = joystick_0[8]  | kb_coin1;
wire m_coin2  = joystick_1[8]  | kb_coin2;
wire m_start1 = joystick_0[9]  | joystick_1[9]  | kb_start1;
wire m_start2 = joystick_0[10] | joystick_1[10] | kb_start2;
wire m_pause  = joystick_0[11] | kb_pause;

// DIP switches arrive from the OSD via ioctl index 254
reg [7:0] dip_sw[8] = '{8'h00,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00};
always @(posedge CLK_49M) begin
	if (ioctl_wr && (ioctl_index == 8'd254) && !ioctl_addr[24:3])
		dip_sw[ioctl_addr[2:0]] <= ioctl_dout;
end

// Guzzler coins are PORT_IMPULSE(2): a press registers for two frames however long it is held
reg       vblank_d = 1'b0;
reg       coin1_d = 1'b0, coin2_d = 1'b0;
reg [1:0] coin1_frames = 2'd0, coin2_frames = 2'd0;
always @(posedge CLK_49M) begin
	vblank_d <= vblank;
	coin1_d  <= m_coin1;
	coin2_d  <= m_coin2;
	if (m_coin1 & ~coin1_d) coin1_frames <= 2'd2;
	else if (vblank & ~vblank_d && coin1_frames != 2'd0) coin1_frames <= coin1_frames - 2'd1;
	if (m_coin2 & ~coin2_d) coin2_frames <= 2'd2;
	else if (vblank & ~vblank_d && coin2_frames != 2'd0) coin2_frames <= coin2_frames - 2'd1;
end
wire coin1_imp = |coin1_frames;
wire coin2_imp = |coin2_frames;

// Per-game port layout and polarity (MAME INPUT_PORTS)
reg [7:0] in_p1, in_p2, in_dsw, in_sys;
always @(*) begin
	in_dsw = dip_sw[0];
	case (game_layout)
		8'd1: begin // Crazy Kong: 4-way + jump, SYSTEM active low
			in_p1  = {m_right1, m_left1, m_down1, m_up1, m_b1_1, 3'b000};
			in_p2  = {m_right2, m_left2, m_down2, m_up2, m_b1_2, 3'b000};
			in_sys = {4'hF, ~m_start2, ~m_start1, ~m_coin2, ~m_coin1};
		end
		8'd3: begin // Swimmer / Guzzler: A000 = P2, A800 = P1, coins and starts share DSW2
			in_p1  = {3'b000, m_b1_2, m_down2, m_up2, m_left2, m_right2};
			in_p2  = {3'b000, m_b1_1, m_down1, m_up1, m_left1, m_right1};
			in_sys = {dip_sw[1][7:4], m_start2, m_start1, coin2_imp, coin1_imp};
		end
		8'd2: begin // River Patrol: P1 port carries the cocktail player
			in_p1  = {m_right2, m_left2, 5'b00000, m_b1_2};
			in_p2  = {m_right1, m_left1, 5'b00000, m_b1_1};
			in_sys = {4'hF, m_start2, m_start1, 1'b1, ~m_coin1};
		end
		default: begin // Crazy Climber: left hand on the d-pad, right hand on Btn 1-4 or the right analog stick
			in_p1  = {m_b1_1 | rstick0[0], m_b2_1 | rstick0[1], m_b3_1 | rstick0[3], m_b4_1 | rstick0[2],
			          m_right1, m_left1, m_down1, m_up1};
			in_p2  = {m_b1_2 | rstick1[0], m_b2_2 | rstick1[1], m_b3_2 | rstick1[3], m_b4_2 | rstick1[2],
			          m_right2, m_left2, m_down2, m_up2};
			in_sys = {3'b000, dip_sw[1][0], m_start2, m_start1, m_coin2, m_coin1};
		end
	endcase
end

// PAUSE SYSTEM
wire [23:0] rgb_out;
pause #(8,8,8,49) pause
(
	.*,
	.clk_sys(CLK_49M),
	.user_button(m_pause),
	.pause_request(1'b0),
	.options(~status[26:25])
);

///////////////                 Video                  ////////////////

wire hblank, vblank;
wire hs, vs;
wire [7:0] r, g, b;
wire ce_pix;

wire rotate_ccw = ~game_flags[7];  // ROT270 sets rotate CCW, ROT90 sets CW
wire no_rotate  = ~game_vert | status[12] | direct_video;
wire flip       = status[11];
screen_rotate screen_rotate(.*);

arcade_video #(260,24) arcade_video
(
	.*,

	.clk_video(CLK_49M),

	.RGB_in(rgb_out),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(~hs),
	.VSync(~vs),

	.fx(status[17:15])
);

///////////////                 Board                  ////////////////

wire flip_x, flip_y;

cclimber_board board
(
	.clk(CLK_49M),
	.reset(reset),
	.ce12(ce12),
	.pause(pause_cpu),

	.swimmer(game_flags[6]),
	.decrypt_en(game_flags[0]),
	.rom_xor(game_flags[2:1]),
	.vol5_en(game_flags[3]),
	.nmi_q3(game_flags[5]),

	.in_p1(in_p1),
	.in_p2(in_p2),
	.in_dsw(in_dsw),
	.in_sys(in_sys),

	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wr0(ioctl_wr & (ioctl_index == 8'd0)),
	.ioctl_wr2(ioctl_wr & (ioctl_index == 8'd2)),

	.video_r(r),
	.video_g(g),
	.video_b(b),
	.video_hs(hs),
	.video_vs(vs),
	.video_hblank(hblank),
	.video_vblank(vblank),
	.ce_pix(ce_pix),

	.crt_flip(status[22]),

	.flip_x(flip_x),
	.flip_y(flip_y),

	.audio(audio)
);

endmodule
