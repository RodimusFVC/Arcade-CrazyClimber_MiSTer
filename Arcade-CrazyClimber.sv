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
wire [127:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire [10:0] ps2_key;
wire        ioctl_download;
wire        ioctl_upload;
wire        ioctl_upload_req;
wire  [7:0] ioctl_din;
wire        ioctl_wr;
wire  [7:0] ioctl_index;
wire [26:0] ioctl_addr27;                     // hps_io's full address: the artwork download can pass 32 MB
wire [24:0] ioctl_addr = ioctl_addr27[24:0];  // every other ioctl user
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
//   layout: 0 Crazy Climber twin stick, 1 Crazy Kong, 2 River Patrol, 3 Swimmer / Guzzler, 4 Cannon Ball, 5 Tangram Q, 6 Yamato, 7 Top Roller
// ROM images: index 0 CC board, 2 Swimmer board, 5 Tangram Q, 6 Yamato, 7 Top Roller; 3 and 4 are reserved for hiscore config / NVRAM
//   flags : [0] decryption PROM, [2:1] ROM XOR mode, [3] volume D4 fitted, [4] vertical (ROT270),
//           [5] latch Q3 drives the NMI mask, [6] Swimmer board (ROMs on index 2), [7] vertical is ROT90
reg [7:0] game_layout = 8'd0;
reg [7:0] game_flags  = 8'd1;
reg [7:0] game_var    = 8'd0;   // byte 2 (optional): [0] Au, [1] Cannon Ball board, [2] Cannon Ball ROM XOR, [3] Tangram Q, [4] Yamato, [5] Top Roller, [6] Le Bagnard

always @(posedge CLK_49M) begin
	if (ioctl_wr && ioctl_index == 8'd1) begin
		if (ioctl_addr == 25'd0) begin game_layout <= ioctl_dout; game_var <= 8'd0; end
		if (ioctl_addr == 25'd1) game_flags  <= ioctl_dout;
		if (ioctl_addr == 25'd2) game_var    <= ioctl_dout;
	end
end

wire game_vert = game_flags[4];
wire vert_view = game_vert & ~status[12];

wire [1:0] ar = status[14:13];

wire        art_fb;                // artwork framebuffer on HDMI: square canvas pixels
wire        art_wait, art_avail;
wire [11:0] art_cw, art_ch;
assign VIDEO_ARX = (!ar) ? (art_fb ? art_cw : vert_view ? 12'd3 : 12'd4) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? (art_fb ? art_ch : vert_view ? 12'd4 : 12'd3) : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"CCLIMBER;;",
	"P1,Video Options;",
	"P1ODE,Aspect Ratio,Original,Full screen,[ARC1],[ARC2];",
	"P1OC,Orientation,Vert,Horz;",
	"P1OB,HDMI Flip,Off,On;",
	"P1OM,CRT Flip,Off,On;",
	"P1O[31:28],H Position (CRT),0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[35:32],V Position (CRT),0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1OFH,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"P2,Pause Options;",
	"P2OP,Pause when OSD is open,On,Off;",
	"P2OQ,Dim video after 10s,On,Off;",
	"-;",
	"P3,High Score Options;",
	"P3OR,Autosave Hiscores,Off,On;",
	"-;",
	"H1P4,Game Options;",
	"H1P4-,Artwork (MAME layout views);",
	"H1P4O[50:48],View,Off,View 1,View 2,View 3,View 4,View 5,View 6,View 7;",
	"H1P4O[51],Backdrop,On,Off;",
	"H1P4O[52],Overlay,On,Off;",
	"H1P4O[53],Bezel,On,Off;",
	"H1P4O[56],Control Panel,On,Off;",
	"H1P4O[54],Side Art,On,Off;",
	"H1P4O[55],Zoom to Screen,Off,On;",
	"H1-;",
	"DIP;",
	"-;",
	"R0,Reset;",
	"J1,Btn 1,Btn 2,Btn 3,Btn 4,Coin,Start 1P,Start 2P,Pause;",
	"jn,A,B,X,Y,Select,Start,R,L;",
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
	.status_menumask({~art_avail, direct_video}),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr27),
	.ioctl_dout(ioctl_dout),
	.ioctl_din(ioctl_din),
	.ioctl_wait(art_wait),
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

// keyboard -> controllers.sv ctl_keyboard (keys now act on press), W / S / A / D through its extra-key
// table.
/* verilator lint_off UNUSED */
wire [12:0] kb;                     // 9 and T are not used on this board
/* verilator lint_on UNUSED */
wire  [3:0] kbx;
ctl_keyboard #(.NX(4), .NXO(4), .XKEYS({24'h10_1D_03, 24'h10_1B_02, 24'h10_1C_01, 24'h10_23_00})) u_kb(.clk(CLK_49M),
	.ps2_key(ps2_key), .pause(pause_cpu), .kb(kb), .kbx(kbx));
wire kb_up = kb[0], kb_down = kb[1], kb_left = kb[2], kb_right = kb[3];
wire kb_rup = kbx[3], kb_rdown = kbx[2], kb_rleft = kbx[1], kb_rright = kbx[0];
wire kb_b1 = kb[4], kb_b2 = kb[5];
wire kb_coin1 = kb[8], kb_coin2 = kb[9], kb_start1 = kb[6], kb_start2 = kb[7], kb_pause = kb[12];

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

// Right analog stick drives the right hand
wire [3:0] rdir0, rdir1;            // {U, D, L, R}
// right-stick directions -> ctl_stick_dirs (+-48 per axis)
ctl_stick_dirs #(.MODE(0), .THRESH(7'd48)) u_rs0(.stick(joystick_r_analog_0), .dir(rdir0));
ctl_stick_dirs #(.MODE(0), .THRESH(7'd48)) u_rs1(.stick(joystick_r_analog_1), .dir(rdir1));
wire [3:0] rstick0 = {rdir0[2], rdir0[3], rdir0[1], rdir0[0]};  // {D,U,L,R}
wire [3:0] rstick1 = {rdir1[2], rdir1[3], rdir1[1], rdir1[0]};

wire m_coin1  = joystick_0[8]  | kb_coin1;
wire m_coin2  = joystick_1[8]  | kb_coin2;
// pads never linked: pad 2's Start gives Start 2 only
wire m_start1 = joystick_0[9]  | kb_start1;
wire m_start2 = joystick_0[10] | joystick_1[10] | joystick_1[9] | kb_start2;
wire m_pause  = joystick_0[11] | kb_pause;

// DIP switches arrive from the OSD via ioctl index 254
reg [7:0] dip_sw[8] = '{8'h00,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00,8'h00};
always @(posedge CLK_49M) begin
	if (ioctl_wr && (ioctl_index == 8'd254) && !ioctl_addr[24:3])
		dip_sw[ioctl_addr[2:0]] <= ioctl_dout;
end

// Swimmer-board coins are PORT_IMPULSE(2): a press is latched, then presented for exactly two whole
// frames starting at the next vblank, however long or briefly it is held
// -> controllers.sv ctl_coin_impulse, paused with the CPU (PAUSE_MODE 1: the frame count holds, a
// press made while paused is discarded).
wire coin1_imp, coin2_imp;
ctl_coin_impulse #(.FRAMES(4'd2), .PAUSE_MODE(1)) u_coin1(.clk(CLK_49M), .pause(pause_cpu), .vblank(vblank), .en(1'b1),
	.coin_raw(m_coin1), .coin(coin1_imp));
ctl_coin_impulse #(.FRAMES(4'd2), .PAUSE_MODE(1)) u_coin2(.clk(CLK_49M), .pause(pause_cpu), .vblank(vblank), .en(1'b1),
	.coin_raw(m_coin2), .coin(coin2_imp));

// Per-game port layout and polarity
reg [7:0] in_p1, in_p2, in_dsw, in_sys, in_sys1, in_sys2;
always @(*) begin
	in_dsw  = dip_sw[0];
	in_sys1 = 8'hFF;
	in_sys2 = 8'hFF;
	case (game_layout)
		8'd7: begin // Top Roller: P1 bits 0-2 are the Coin B switches; SYSTEM active low
			in_p1  = {m_right1, m_left1, m_down1, m_up1, m_b1_1, dip_sw[1][2:0]};
			in_p2  = {m_right2, m_left2, m_down2, m_up2, m_b1_2, 3'b000};
			in_sys = {4'hF, ~m_start2, ~m_start1, ~m_coin1, ~m_coin2};
		end
		8'd6: begin // Yamato: 8-way + 2 buttons; the US set reads its Coin B switches (DSW2) through P1/P2 bits 0-1
			in_p1  = {m_right1, m_left1, m_down1, m_up1, m_b2_1, m_b1_1, dip_sw[1][1:0]};
			in_p2  = {m_right2, m_left2, m_down2, m_up2, m_b2_2, m_b1_2, dip_sw[1][3:2]};
			in_sys = {4'b0000, m_start2, m_start1, m_coin1, m_coin2};
		end
		8'd5: begin // Tangram Q: 2-way + button; B000 = DSW2, B800 = DSW1; coins/starts on 8000/8020 (active low)
			in_p1   = {4'b0000, m_left1, m_right1, m_b1_1, 1'b0};
			in_p2   = {4'b0000, m_left2, m_right2, m_b1_2, 1'b0};
			in_dsw  = dip_sw[1];
			in_sys  = dip_sw[0];
			in_sys1 = {2'b11, ~m_coin1, 2'b11, ~m_start1, ~m_start2, 1'b1};
			in_sys2 = {4'hF, ~m_coin2, 3'b111};
		end
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
		8'd4: begin // Cannon Ball: Crazy Kong ports with P1 right/left swapped
			in_p1  = {m_left1, m_right1, m_down1, m_up1, m_b1_1, 3'b000};
			in_p2  = {m_right2, m_left2, m_down2, m_up2, m_b1_2, 3'b000};
			in_sys = {4'hF, ~m_start2, ~m_start1, ~m_coin2, ~m_coin1};
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
	.pause_request(hs_pause),
	.options(~status[26:25])
);

///////////////                 Video                  ////////////////

wire hblank, vblank;
wire hs, vs;
wire [7:0] r, g, b;
wire ce_pix;
wire bd_hblank, bd_vblank, bd_hs, bd_vs;
wire [7:0] bd_r, bd_g, bd_b;

// MAME artwork (ioctl index 10: indexes 0-7 are ROM layouts / config; OSD Game Options page): native composite on the
// core video (one pixel late), full view through the DDR3 framebuffer on HDMI
wire        art_run, art_ddr;
wire [31:0] art_fb_base;
wire  [7:0] art_burstcnt, art_be;
wire [28:0] art_addr;
wire [63:0] art_din;
wire        art_rd, art_we, art_clk;
artwork #(.IDX(8'd10)) artwork
(
	.clk(CLK_49M),
	.sel({1'b0, status[50:48]}), .layer_off({status[56], status[53:51]}), .side_off(status[54]), .zoom(status[55]),
	.crt_flip(status[22]), .hdmi_flip(status[11]), .turn(game_vert & status[12]), .avail(art_avail),
	.hdmi_w(HDMI_WIDTH), .hdmi_h(HDMI_HEIGHT),
	.ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr27), .ioctl_dout(ioctl_dout), .ioctl_wait(art_wait),
	.ce_pix(ce_pix),
	.hs_in(bd_hs), .vs_in(bd_vs), .hblank_in(bd_hblank), .vblank_in(bd_vblank), .rgb_in({bd_r, bd_g, bd_b}),
	.hs_out(hs), .vs_out(vs), .hblank_out(hblank), .vblank_out(vblank), .rgb_out({r, g, b}),
	.running(art_run), .ddr_owner(art_ddr), .canvas_w(art_cw), .canvas_h(art_ch),
	.fb_base(art_fb_base), .fb_vbl(FB_VBL),
	.DDRAM_CLK(art_clk), .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(art_burstcnt), .DDRAM_ADDR(art_addr),
	.DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(art_rd),
	.DDRAM_DIN(art_din), .DDRAM_BE(art_be), .DDRAM_WE(art_we)
);
// Orientation Horz (rotated monitor): the artwork turns its own view, so it keeps the framebuffer
assign art_fb = art_run & ~direct_video;

wire rotate_ccw = ~game_flags[7];  // ROT270 sets rotate CCW, ROT90 sets CW
wire no_rotate  = ~game_vert | status[12] | direct_video;
wire flip       = status[11];
wire        sr_fb_en, sr_clk, sr_rd, sr_we;
wire  [4:0] sr_fb_format;
wire [11:0] sr_fb_w, sr_fb_h;
wire [31:0] sr_fb_base;
wire [13:0] sr_fb_stride;
wire  [7:0] sr_burstcnt, sr_be;
wire [28:0] sr_addr;
wire [63:0] sr_din;
screen_rotate screen_rotate
(
	.*,
	.FB_EN(sr_fb_en), .FB_FORMAT(sr_fb_format), .FB_WIDTH(sr_fb_w), .FB_HEIGHT(sr_fb_h),
	.FB_BASE(sr_fb_base), .FB_STRIDE(sr_fb_stride),
	.DDRAM_CLK(sr_clk), .DDRAM_BURSTCNT(sr_burstcnt), .DDRAM_ADDR(sr_addr), .DDRAM_DIN(sr_din),
	.DDRAM_BE(sr_be), .DDRAM_WE(sr_we), .DDRAM_RD(sr_rd)
);

// the artwork takes the framebuffer while it draws, and DDR3 while it loads or draws
assign FB_EN     = art_fb | sr_fb_en;
assign FB_FORMAT = art_fb ? 5'b00110  : sr_fb_format;
assign FB_WIDTH  = art_fb ? art_cw    : sr_fb_w;
assign FB_HEIGHT = art_fb ? art_ch    : sr_fb_h;
assign FB_BASE   = art_fb ? art_fb_base : sr_fb_base;
assign FB_STRIDE = art_fb ? 14'd8192  : sr_fb_stride;
assign DDRAM_CLK      = CLK_49M;
assign DDRAM_BURSTCNT = art_ddr ? art_burstcnt : sr_burstcnt;
assign DDRAM_ADDR     = art_ddr ? art_addr : sr_addr;
assign DDRAM_DIN      = art_ddr ? art_din : sr_din;
assign DDRAM_BE       = art_ddr ? art_be : sr_be;
assign DDRAM_WE       = art_ddr ? art_we : sr_we;
assign DDRAM_RD       = art_ddr ? art_rd : sr_rd;

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

cclimber_dispatcher board
(
	.clk(CLK_49M),
	.reset(reset),
	.ce12(ce12),
	.pause(pause_cpu),

	.swimmer(game_flags[6]),
	.au(game_var[0]),
	.cannonb(game_var[1]),
	.cb_xor(game_var[2]),
	.tangramq(game_var[3]),
	.yamato(game_var[4]),
	.toprollr(game_var[5]),
	.bagmanf(game_var[6]),
	.decrypt_en(game_flags[0]),
	.rom_xor(game_flags[2:1]),
	.vol5_en(game_flags[3]),
	.nmi_q3(game_flags[5]),

	.in_p1(in_p1),
	.in_p2(in_p2),
	.in_dsw(in_dsw),
	.in_sys(in_sys),
	.in_sys1(in_sys1),
	.in_sys2(in_sys2),

	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wr0(ioctl_wr & (ioctl_index == 8'd0)),
	.ioctl_wr2(ioctl_wr & (ioctl_index == 8'd2)),
	.ioctl_wr5(ioctl_wr & (ioctl_index == 8'd5)),
	.ioctl_wr6(ioctl_wr & (ioctl_index == 8'd6)),
	.ioctl_wr7(ioctl_wr & (ioctl_index == 8'd7)),

	.video_r(bd_r),
	.video_g(bd_g),
	.video_b(bd_b),
	.video_hs(bd_hs),
	.video_vs(bd_vs),
	.video_hblank(bd_hblank),
	.video_vblank(bd_vblank),
	.ce_pix(ce_pix),

	.crt_flip(status[22]),
	.h_adj(status[31:28]),
	.v_adj(status[35:32]),

	.flip_x(flip_x),
	.flip_y(flip_y),

	.audio(audio),

	.hs_address(hs_address),
	.hs_data_in(hs_data_in),
	.hs_data_out(hs_data_out),
	.hs_write(hs_write_enable)
);

// Hiscore: config = MRA index 3, dump = index 4; RAM via the board's second port while the CPU is paused
wire [15:0] hs_address;
wire  [7:0] hs_data_in;
wire  [7:0] hs_data_out;
wire        hs_write_enable;
wire        hs_access_read;
wire        hs_access_write;
wire        hs_pause;
wire        hs_configured;

hiscore #(
	.HS_ADDRESSWIDTH(16),
	.CFG_ADDRESSWIDTH(4),
	.CFG_LENGTHWIDTH(2)
) hi (
	.*,
	.clk(CLK_49M),
	.paused(pause_cpu),
	.autosave(status[27]),
	.ram_address(hs_address),
	.data_from_ram(hs_data_out),
	.data_to_ram(hs_data_in),
	.data_from_hps(ioctl_dout),
	.data_to_hps(ioctl_din),
	.ram_write(hs_write_enable),
	.ram_intent_read(hs_access_read),
	.ram_intent_write(hs_access_write),
	.pause_cpu(hs_pause),
	.configured(hs_configured)
);

endmodule
