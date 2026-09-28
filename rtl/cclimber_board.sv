//============================================================================
//
//  Crazy Climber board (Nichibutsu CCG-1/CCG-2, Crazy Kong derivatives)
//  and Swimmer board (Tehkan / Centuri A102-401 + B102-402)
//  Copyright (C) 2026 Rodimus
//
//  Video timing and scanout pipeline ported from Crazy Climber FPGA by
//  Dar (darfpga@aol.fr, http://darfpga.blogspot.fr)
//  Memory maps, opcode decryption and sound model per MAME cclimber.cpp
//  (Nicola Salmoria)
//
//============================================================================

module cclimber_board
(
    input               clk,            // 49.152 MHz
    input               reset,          // active high
    input               ce12,           // 12.288 MHz enable = 2x pixel
    input               pause,

    input               swimmer,        // Swimmer board (3bpp, sound CPU)
    input               au,             // Au: Swimmer board with 8K planes and palette RAM
    input               decrypt_en,     // dm7052 opcode decryption PROM fitted
    input         [1:0] rom_xor,        // 0 none, 1 rpatrol, 2 ckongb, 3 dking
    input               vol5_en,        // volume D4 resistor fitted
    input               nmi_q3,         // latch Q3 also drives the NMI mask (ckongb bootleg)

    input         [7:0] in_p1,          // $A000
    input         [7:0] in_p2,          // $A800
    input         [7:0] in_dsw,         // $B000
    input         [7:0] in_sys,         // $B800

    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               ioctl_wr0,      // ioctl index 0 (Crazy Climber layout)
    input               ioctl_wr2,      // ioctl index 2 (Swimmer layout)

    output        [7:0] video_r,
    output        [7:0] video_g,
    output        [7:0] video_b,
    output reg          video_hs = 1'b1,
    output reg          video_vs = 1'b1,
    output reg          video_hblank = 1'b1,
    output reg          video_vblank = 1'b1,
    output              ce_pix,

    input               crt_flip,       // OSD CRT Flip, XORed with the game's flip latch

    output              flip_x,
    output              flip_y,

    output signed [15:0] audio
);

//------------------------------------------------------- ROM load map --------------------------------------------------------//

// Layouts in rtl/ram_rom/rom_loader.sv
wire prog_cs, tile0_cs, tile1_cs, bs0_cs, bs1_cs, smp_cs, pal_cs, bspal_cs, dprom_cs;

selector rom_sel
(
    .ioctl_addr(ioctl_addr),
    .prog_cs(prog_cs),
    .tile0_cs(tile0_cs),
    .tile1_cs(tile1_cs),
    .bs0_cs(bs0_cs),
    .bs1_cs(bs1_cs),
    .smp_cs(smp_cs),
    .pal_cs(pal_cs),
    .bspal_cs(bspal_cs),
    .dprom_cs(dprom_cs)
);

wire       sw_prog_cs, sw_himem_cs, sw_snd_cs, sw_pal_lo_cs, sw_pal_hi_cs, sw_bspal_cs;
wire [2:0] sw_tile_cs, sw_bs_cs;

selector_swimmer rom_sel_sw
(
    .ioctl_addr(ioctl_addr),
    .prog_cs(sw_prog_cs),
    .himem_cs(sw_himem_cs),
    .snd_cs(sw_snd_cs),
    .tile_cs(sw_tile_cs),
    .bs_cs(sw_bs_cs),
    .pal_lo_cs(sw_pal_lo_cs),
    .pal_hi_cs(sw_pal_hi_cs),
    .bspal_cs(sw_bspal_cs)
);

wire dl_prog   = (ioctl_wr0 & prog_cs) | (ioctl_wr2 & sw_prog_cs);
wire dl_himem  = ioctl_wr2 & sw_himem_cs;
wire dl_snd    = ioctl_wr2 & sw_snd_cs;
wire dl_tile0  = (ioctl_wr0 & tile0_cs) | (ioctl_wr2 & sw_tile_cs[0]);
wire dl_tile1  = (ioctl_wr0 & tile1_cs) | (ioctl_wr2 & sw_tile_cs[1]);
wire dl_tile2  = ioctl_wr2 & sw_tile_cs[2];
wire dl_bs0    = (ioctl_wr0 & bs0_cs) | (ioctl_wr2 & sw_bs_cs[0]);
wire dl_bs1    = (ioctl_wr0 & bs1_cs) | (ioctl_wr2 & sw_bs_cs[1]);
wire dl_bs2    = ioctl_wr2 & sw_bs_cs[2];
wire dl_smp    = ioctl_wr0 & smp_cs;
wire dl_pal    = ioctl_wr0 & pal_cs;
wire dl_pal_lo = ioctl_wr2 & sw_pal_lo_cs;
wire dl_pal_hi = ioctl_wr2 & sw_pal_hi_cs;
wire dl_bspal  = (ioctl_wr0 & bspal_cs) | (ioctl_wr2 & sw_bspal_cs);
wire dl_dprom  = ioctl_wr0 & dprom_cs;

// Plane RAM addresses: tile slots are 8K on both indexes, big sprite planes 2K (index 0) / 4K (index 2)
wire [12:0] dl_tile_addr = ioctl_addr[12:0];
wire [11:0] dl_bs_addr   = ioctl_wr2 ? ioctl_addr[11:0] : {1'b0, ioctl_addr[10:0]};

//------------------------------------------------------- Video timing --------------------------------------------------------//

// Both boards: MCLK = 18.432/3, H counts 128..511 (384), V counts 248..511 (264)
reg ena_pixel = 1'b0;
always_ff @(posedge clk) if (ce12) ena_pixel <= ~ena_pixel;

wire ce_px = ce12 & ena_pixel;
assign ce_pix = ce_px;

reg [8:0] hcnt   = 9'd511;
reg [8:0] vcnt   = 9'd511;
reg [8:0] vcnt_r = 9'd511;

always_ff @(posedge clk) begin
    if (ce_px) begin
        if (hcnt == 9'd511) begin
            hcnt   <= 9'd128;
            vcnt_r <= vcnt;
        end else
            hcnt <= hcnt + 9'd1;

        if (hcnt == 9'd175)
            vcnt <= (vcnt == 9'd511) ? 9'd248 : vcnt + 9'd1;

        if (hcnt == 9'd175)      video_hs <= 1'b0;
        else if (hcnt == 9'd204) video_hs <= 1'b1;

        if (vcnt == 9'd511)      video_vs <= 1'b0;
        else if (vcnt == 9'd250) video_vs <= 1'b1;

        // +8 for the shift register, +1 pixel; vcnt has already stepped, so rows shown are 272..495 (y 16..239)
        if (hcnt == 9'd137) video_hblank <= 1'b1;
        else if (hcnt == 9'd264) begin
            video_hblank <= 1'b0;
            if (vcnt == 9'd497)      video_vblank <= 1'b1;
            else if (vcnt == 9'd273) video_vblank <= 1'b0;
        end
    end
end

wire       is_sprite = ~hcnt[8];
wire [2:0] sprite    = hcnt[6:4];
wire [4:0] x_tile    = hcnt[7:3];
wire [2:0] x_pixel   = hcnt[2:0];
wire [4:0] y_tile    = vcnt_r[7:3];
wire [2:0] y_pixel   = vcnt_r[2:0];

// HINV/VINV: the '86 banks invert the counters feeding video addressing; blanking and NMI stay raw
wire       hinv      = flip_x ^ crt_flip;
wire       vinv      = flip_y ^ crt_flip;
wire [7:0] y_line    = vcnt_r[7:0] ^ {8{vinv}};
wire [4:0] x_tile_v  = x_tile ^ {5{hinv}};

// Q0 NMI enable, Q1 flip X, Q2 flip Y; Q4 sample trigger (CC) / Q3 side background, Q4 palette bank (Swimmer)
reg [7:0] mainlatch = 8'h00;
assign flip_x = mainlatch[1];
assign flip_y = mainlatch[2];
wire   sidebg_en  = swimmer & ~au & mainlatch[3];
wire   pal_bank   = swimmer & ~au & mainlatch[4];

// Z80 clock is ~H0: it rises as hcnt steps odd -> even
wire cpu_rise = ce_px &  hcnt[0];
wire cpu_fall = ce_px & ~hcnt[0];

//------------------------------------------------------- Z80 -----------------------------------------------------------------//

wire [15:0] cpu_addr;
wire  [7:0] cpu_do;
reg   [7:0] cpu_di;
wire        cpu_m1_n, cpu_mreq_n, cpu_iorq_n, cpu_rd_n, cpu_wr_n;
reg         cpu_nmi_n = 1'b1;

T80s #(.Mode(0), .T2Write(1), .IOWait(1)) z80
(
    .RESET_n(~reset),
    .CLK(clk),
    .CEN(cpu_rise & ~pause),
    .WAIT_n(1'b1),
    .INT_n(1'b1),
    .NMI_n(cpu_nmi_n),
    .BUSRQ_n(1'b1),
    .M1_n(cpu_m1_n),
    .MREQ_n(cpu_mreq_n),
    .IORQ_n(cpu_iorq_n),
    .RD_n(cpu_rd_n),
    .WR_n(cpu_wr_n),
    .RFSH_n(),
    .HALT_n(),
    .BUSAK_n(),
    .OUT0(1'b0),
    .A(cpu_addr),
    .DI(cpu_di),
    .DO(cpu_do)
);

//------------------------------------------------------- Address decode ------------------------------------------------------//

wire       mem_wr   = ~cpu_mreq_n & ~cpu_wr_n;
wire [4:0] a_hi     = cpu_addr[15:11];

// CC: ROM 0000-5FFF, RAM 6000-6FFF.  Swimmer: ROM 0000-7FFF + E000-FFFF, RAM C000-CFFF (Guzzler)
wire rom_cs   = swimmer ? (~cpu_addr[15] | (cpu_addr[15:13] == 3'b111)) : (cpu_addr < 16'h6000);
wire ram6_cs  = cpu_addr[15:12] == (swimmer ? 4'hC : 4'h6);
wire ram8_cs  = a_hi == 5'b10000;                                   // 8000-87FF
wire bsram_cs = swimmer ? (a_hi == 5'b10001) : (cpu_addr[15:8] == 8'h88);
wire tile_cs  = a_hi == 5'b10010;                                   // 9000-97FF
wire color_cs = a_hi == 5'b10011;                                   // 9800-9FFF

wire latch_we = mem_wr & (a_hi == 5'b10100);                        // A000-A007 LS259
wire a800_we  = mem_wr & (a_hi == 5'b10101);                        // sample rate / sound latch
wire b000_we  = mem_wr & (a_hi == 5'b10110);                        // sample volume
wire b800_we  = mem_wr & (a_hi == 5'b10111);                        // background colour (Swimmer)

//------------------------------------------------------- Program ROM ---------------------------------------------------------//

wire [7:0] rom_lo_do, rom_hi_do;

dpram_dc #(.widthad_a(15)) prog_rom
(
    .clock_a(clk),
    .address_a(ioctl_addr[14:0]),
    .data_a(ioctl_dout),
    .wren_a(dl_prog),

    .clock_b(clk),
    .address_b(cpu_addr[14:0]),
    .q_b(rom_lo_do)
);

dpram_dc #(.widthad_a(13)) prog_rom_hi
(
    .clock_a(clk),
    .address_a(ioctl_addr[12:0]),
    .data_a(ioctl_dout),
    .wren_a(dl_himem),

    .clock_b(clk),
    .address_b(cpu_addr[12:0]),
    .q_b(rom_hi_do)
);

wire [7:0] rom_do = cpu_addr[15] ? rom_hi_do : rom_lo_do;

// Bootleg data-bus inverters (MAME init_rpatrol / init_ckongb / init_dking)
reg [7:0] rom_xor_mask;
always_comb begin
    rom_xor_mask = 8'h00;
    case (rom_xor)
        2'd1: if (cpu_addr < 16'h5000) rom_xor_mask = cpu_addr[0] ? 8'h5B : 8'h79;
        2'd2: rom_xor_mask = 8'hF0;
        2'd3: if (cpu_addr < 16'h5000 &&
                  ((cpu_addr[11:0] >= 12'h500 && cpu_addr[11:0] < 12'h800) || cpu_addr[11:0] >= 12'hD00))
                  rom_xor_mask = 8'hFF;
        default: ;
    endcase
end

wire [7:0] rom_src = rom_do ^ rom_xor_mask;

// Opcode decryption PROM (dm7052, 256x4) in the CPU block, indexed by data bits and A0
reg  [3:0] dprom [256];
always_ff @(posedge clk) if (dl_dprom) dprom[ioctl_addr[7:0]] <= ioctl_dout[3:0];

wire [7:0] dp_idx = {1'b0, cpu_addr[0], rom_src[7], rom_src[1], rom_src[4], rom_src[6], rom_src[2], rom_src[0]};
wire [3:0] dp     = dprom[dp_idx];
wire [7:0] rom_dec = (rom_src & 8'hAA) | {1'b0, dp[2], 1'b0, dp[3], 1'b0, dp[1], 1'b0, dp[0]};

wire [7:0] rom_data = (decrypt_en & ~cpu_m1_n) ? rom_dec : rom_src;

//------------------------------------------------------- Work RAM ------------------------------------------------------------//

wire [7:0] ram6_do, ram8_do;

spram #(.DATA_WIDTH(8), .ADDR_WIDTH(12)) ram6
(
    .clk(clk),
    .addr(cpu_addr[11:0]),
    .data(cpu_do),
    .q(ram6_do),
    .we(mem_wr & ram6_cs)
);

// CC: 1K mirrored through 8000-87FF.  Swimmer: 2K
spram #(.DATA_WIDTH(8), .ADDR_WIDTH(11)) ram8
(
    .clk(clk),
    .addr({swimmer & cpu_addr[10], cpu_addr[9:0]}),
    .data(cpu_do),
    .q(ram8_do),
    .we(mem_wr & ram8_cs)
);

//------------------------------------------------------- CPU read mux --------------------------------------------------------//

wire [7:0] ay_dout;
wire [7:0] bs_ram_do, tile_ram_do, color_ram_do;

always_comb begin
    if (~cpu_iorq_n)
        cpu_di = swimmer ? 8'hFF : ay_dout;
    else if (rom_cs)
        cpu_di = rom_data;
    else if (ram6_cs)
        cpu_di = ram6_do;
    else case (a_hi)
        5'b10000: cpu_di = ram8_do;
        5'b10001: cpu_di = bs_ram_do;
        5'b10010: cpu_di = tile_ram_do;
        5'b10011: cpu_di = color_ram_do;
        5'b10100: cpu_di = in_p1;
        5'b10101: cpu_di = in_p2;
        5'b10110: cpu_di = in_dsw;
        5'b10111: cpu_di = in_sys;
        default:  cpu_di = 8'h00;
    endcase
end

//------------------------------------------------------- LS259 latch / NMI ---------------------------------------------------//

// NMI mask follows the last write to Q0 (or Q3 on the ckongb board)
reg nmi_en = 1'b0;

always_ff @(posedge clk) begin
    if (reset) begin
        mainlatch <= 8'h00;
        nmi_en    <= 1'b0;
    end else if (cpu_fall && latch_we) begin
        mainlatch[cpu_addr[2:0]] <= cpu_do[0];
        if (cpu_addr[2:0] == 3'd0 || (nmi_q3 && cpu_addr[2:0] == 3'd3))
            nmi_en <= cpu_do[0];
    end
end

// NMI latched at line 224 and held until the mask is cleared
always_ff @(posedge clk) begin
    if (!nmi_en)
        cpu_nmi_n <= 1'b1;
    else if (ce12 && y_tile == 5'b11100 && y_pixel == 3'b000)
        cpu_nmi_n <= 1'b0;
end

//------------------------------------------------------- Big sprite registers ------------------------------------------------//

reg       bs_prio = 1'b0;               // ctrl 0 bit 0: big sprite under sprites
reg [5:0] attr_big_sprite = 6'd0;       // ctrl 1
reg [7:0] y_big_sprite = 8'd0;          // ctrl 2
reg [7:0] x_big_sprite = 8'd0;          // ctrl 3

// CC 98DC-98DF, Swimmer 98FC-98FF
wire bs_ctrl_cs = cpu_addr[15:2] == (swimmer ? 14'h263F : 14'h2637);

always_ff @(posedge clk) begin
    if (ce12 && mem_wr && bs_ctrl_cs) begin
        case (cpu_addr[1:0])
            2'd0: bs_prio         <= cpu_do[0];
            2'd1: attr_big_sprite <= cpu_do[5:0];
            2'd2: y_big_sprite    <= cpu_do;
            2'd3: x_big_sprite    <= cpu_do;
        endcase
    end
end

// Swimmer background colour register ($B800)
reg [7:0] bgcolor = 8'd0;
always_ff @(posedge clk) if (ce12 && b800_we && swimmer && !au) bgcolor <= cpu_do;

// Au palette RAM: B800-B87F (mirror 0780), 64 x xBGR_333 big-endian words; even byte = B, odd byte = G/R
reg [7:0] aupal_b  [64];
reg [7:0] aupal_gr [64];
always_ff @(posedge clk) begin
    if (ce12 && b800_we && au) begin
        if (cpu_addr[0]) aupal_gr[cpu_addr[6:1]] <= cpu_do;
        else             aupal_b[cpu_addr[6:1]]  <= cpu_do;
    end
end

//------------------------------------------------------- Colour RAM (scroll, sprites, attributes) ----------------------------//

// 9800-9FFF with A5 not connected: scroll at 000-01F, sprites at 040-05F, attributes at 200-3FF
wire [9:0] cpu_addr_mod = {cpu_addr[10:6], cpu_addr[4:0]};

wire [7:0] y_line_shift;

reg  [9:0] color_ram_addr = 10'd0;
reg        color_ram_we = 1'b0;
reg  [7:0] y_sp_bg = 8'd0, attr_sp_bg = 8'd0, attr_sp = 8'd0, x_sprite = 8'd0;

always_ff @(posedge clk) begin
    if (ce12) begin
        color_ram_we <= 1'b0;
        case (x_pixel)
            3'b000: begin
                color_ram_addr <= is_sprite ? {5'b00010, sprite, 2'b10} : {5'b00000, x_tile_v};
                if (ena_pixel) y_sp_bg <= color_ram_do;
            end
            3'b010: begin
                color_ram_addr <= is_sprite ? {5'b00010, sprite, 2'b01} : {1'b1, y_line_shift[7:4], x_tile_v};
                if (ena_pixel) attr_sp_bg <= color_ram_do;
            end
            3'b100: begin
                color_ram_addr <= is_sprite ? {5'b00010, sprite, 2'b00} : 10'd0;
                if (ena_pixel) attr_sp <= color_ram_do;
            end
            3'b110: begin
                color_ram_addr <= is_sprite ? {5'b00010, sprite, 2'b11} : 10'd0;
                if (ena_pixel) x_sprite <= color_ram_do;
            end
            default: begin
                color_ram_addr <= cpu_addr_mod;
                color_ram_we   <= mem_wr & color_cs;
            end
        endcase
    end
end

spram #(.DATA_WIDTH(8), .ADDR_WIDTH(10)) color_ram
(
    .clk(clk),
    .addr(color_ram_addr),
    .data(cpu_do),
    .q(color_ram_do),
    .we(color_ram_we)
);

//------------------------------------------------------- Tile RAM ------------------------------------------------------------//

reg [9:0] tile_ram_addr = 10'd0;
reg       tile_ram_we = 1'b0;

always_ff @(posedge clk) begin
    if (ce12) begin
        tile_ram_we <= 1'b0;
        if (x_pixel == 3'b100)
            tile_ram_addr <= {y_line_shift[7:3], x_tile_v};
        else begin
            tile_ram_addr <= cpu_addr[9:0];
            tile_ram_we   <= mem_wr & tile_cs;
        end
    end
end

spram #(.DATA_WIDTH(8), .ADDR_WIDTH(10)) tile_ram
(
    .clk(clk),
    .addr(tile_ram_addr),
    .data(cpu_do),
    .q(tile_ram_do),
    .we(tile_ram_we)
);

//------------------------------------------------------- Tile / sprite graphics ----------------------------------------------//

assign y_line_shift = y_line + y_sp_bg + 8'd1;

reg  [12:0] tile_graph_rom_addr = 13'd0;
reg   [7:0] bg_tile_code = 8'd0;
reg   [4:0] tile_color_r = 5'd0;
reg   [7:0] tile_graph1_r = 8'd0, tile_graph2_r = 8'd0, tile_graph3_r = 8'd0;
reg         is_sprite_r = 1'b0;
reg         keep_sprite = 1'b0;
wire  [7:0] tile_rom0_do, tile_rom1_do, tile_rom2_do;

function automatic [7:0] bitrev8(input [7:0] d);
    bitrev8 = {d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7]};
endfunction

reg [4:0] sp_row_xor;
always_comb begin
    case (attr_sp[7:6])
        2'b00:   sp_row_xor = 5'b00000;
        2'b01:   sp_row_xor = 5'b01000;
        2'b10:   sp_row_xor = 5'b10111;
        default: sp_row_xor = 5'b11111;
    endcase
end

// Code bank bits: CC {attr4, attr5}; Swimmer attr4 only (4K planes, 512 chars / 128 sprites); Au {attr5, attr4}
wire [1:0] code_hi = au      ? {attr_sp_bg[5], attr_sp_bg[4]} :
                     swimmer ? {1'b0, attr_sp_bg[4]} : {attr_sp_bg[4], attr_sp_bg[5]};

always_ff @(posedge clk) begin
    if (ce12) begin
        case (x_pixel)
            3'b100: if (ena_pixel) bg_tile_code <= tile_ram_do;

            3'b110: begin
                if (is_sprite)
                    tile_graph_rom_addr <= {code_hi, attr_sp[5:0],
                                            {y_line_shift[3], x_tile[0], y_line_shift[2:0]} ^ sp_row_xor};
                else
                    tile_graph_rom_addr <= {code_hi, bg_tile_code,
                                            attr_sp_bg[7] ? ~y_line_shift[2:0] : y_line_shift[2:0]};
            end

            3'b111: if (ena_pixel) begin
                tile_color_r <= {pal_bank, attr_sp_bg[3:0]};
                if ((is_sprite & attr_sp[6]) | (~is_sprite & attr_sp_bg[6])) begin
                    tile_graph1_r <= bitrev8(tile_rom0_do);
                    tile_graph2_r <= bitrev8(tile_rom1_do);
                    tile_graph3_r <= bitrev8(tile_rom2_do);
                end else begin
                    tile_graph1_r <= tile_rom0_do;
                    tile_graph2_r <= tile_rom1_do;
                    tile_graph3_r <= tile_rom2_do;
                end
                is_sprite_r <= is_sprite;
                keep_sprite <= (y_line_shift[7:4] == 4'b1111) && (x_sprite != 8'h00) && (y_sp_bg != 8'h00);
            end

            default: ;
        endcase
    end
end

// Plane order follows the MAME "tile" region: first plane = pixel MSB
dpram_dc #(.widthad_a(13)) tile_rom0
(
    .clock_a(clk),
    .address_a(dl_tile_addr),
    .data_a(ioctl_dout),
    .wren_a(dl_tile0),

    .clock_b(clk),
    .address_b(tile_graph_rom_addr),
    .q_b(tile_rom0_do)
);

dpram_dc #(.widthad_a(13)) tile_rom1
(
    .clock_a(clk),
    .address_a(dl_tile_addr),
    .data_a(ioctl_dout),
    .wren_a(dl_tile1),

    .clock_b(clk),
    .address_b(tile_graph_rom_addr),
    .q_b(tile_rom1_do)
);

dpram_dc #(.widthad_a(13)) tile_rom2
(
    .clock_a(clk),
    .address_a(dl_tile_addr),
    .data_a(ioctl_dout),
    .wren_a(dl_tile2),

    .clock_b(clk),
    .address_b(tile_graph_rom_addr),
    .q_b(tile_rom2_do)
);

// Pixel = {colour, plane bits}: CC {0, 0, colour4, 2 bits}, Swimmer {bank, colour4, 3 bits}
wire [2:0] x_sel = (hinv & ~is_sprite_r) ? x_pixel : ~x_pixel;
wire [7:0] pixel_color = swimmer ? {tile_color_r, tile_graph1_r[x_sel], tile_graph2_r[x_sel], tile_graph3_r[x_sel]}
                                 : {2'b00, tile_color_r[3:0], tile_graph1_r[x_sel], tile_graph2_r[x_sel]};

function automatic pix_on(input sw, input [7:0] p);
    pix_on = sw ? (p[2:0] != 3'd0) : (p[1:0] != 2'd0);
endfunction

//------------------------------------------------------- Sprite line buffer --------------------------------------------------//

reg  [8:0] addr_ram_sprite = 9'd0;

// Swimmer draws sprites one pixel left of CC (MAME x vs x+1, flipped 240-x vs 242-x)
wire [8:0] sprite_x_load = {1'b0, x_sprite ^ {8{hinv}}} - {8'd0, swimmer};

always_ff @(posedge clk) begin
    if (ce12) begin
        if (ena_pixel)
            addr_ram_sprite <= (hinv & is_sprite_r) ? addr_ram_sprite - 9'd1 : addr_ram_sprite + 9'd1;
        if (is_sprite && x_pixel == 3'b111 && ena_pixel && !x_tile[0])
            addr_ram_sprite <= sprite_x_load;
        if (!is_sprite && x_pixel == 3'b111 && ena_pixel && x_tile == 5'd0)
            addr_ram_sprite <= 9'd1;
    end
end

// Read-and-clear during display, first-sprite-wins write during the sprite fetch
wire [7:0] sprite_pixel_color;
wire       sprite_hit   = pix_on(swimmer, sprite_pixel_color);
wire [7:0] sprite_wdata = is_sprite_r ? (sprite_hit ? sprite_pixel_color : pixel_color) : 8'd0;
wire       sprite_we    = ce_px & (is_sprite_r ? (keep_sprite & ~addr_ram_sprite[8]) : 1'b1);

spram #(.DATA_WIDTH(8), .ADDR_WIDTH(8)) sprite_line
(
    .clk(clk),
    .addr(addr_ram_sprite[7:0]),
    .data(sprite_wdata),
    .q(sprite_pixel_color),
    .we(sprite_we)
);

reg [7:0] pixel_color_r = 8'd0;
reg       sprite_on_r = 1'b0;
reg       pf_clear_r = 1'b1;

always_ff @(posedge clk) begin
    if (ce_px) begin
        pixel_color_r <= sprite_hit ? sprite_pixel_color : pixel_color;
        sprite_on_r   <= sprite_hit;
        pf_clear_r    <= ~sprite_hit & ~pix_on(swimmer, pixel_color);
    end
end

//------------------------------------------------------- Big sprite ----------------------------------------------------------//

wire [7:0] y_line_bs = y_line + y_big_sprite + 8'd1;

reg  [7:0] x_bs_cnt = 8'd0;
reg  [7:0] bs_ram_addr = 8'd0;
reg        bs_ram_we = 1'b0;
reg  [7:0] bs_tile_code = 8'd0, bs_tile_code_r = 8'd0;
reg  [7:0] bs_graph1 = 8'd0, bs_graph2 = 8'd0, bs_graph3 = 8'd0;
reg  [7:0] bs_graph1_d = 8'd0, bs_graph2_d = 8'd0, bs_graph3_d = 8'd0;

// Visibility (MAME: only the lower-right quadrant of the 32x32 map) travels with the tile through the
// same pipeline stages as its pixels, so the window edge lands exactly on the map tile boundary
reg        bs_vis_addr = 1'b0, bs_vis_code = 1'b0, bs_vis_r = 1'b0, bs_vis_g = 1'b0;
reg  [7:0] bs_vis_d = 8'd0;
wire [7:0] bs_rom0_do, bs_rom1_do, bs_rom2_do;

reg [7:0] xy_big_sprite;
always_comb begin
    case (attr_big_sprite[5:4])
        2'b01:   xy_big_sprite = { y_line_bs[6:3], ~x_bs_cnt[6:3]};
        2'b11:   xy_big_sprite = {~y_line_bs[6:3], ~x_bs_cnt[6:3]};
        2'b00:   xy_big_sprite = { y_line_bs[6:3],  x_bs_cnt[6:3]};
        default: xy_big_sprite = {~y_line_bs[6:3],  x_bs_cnt[6:3]};
    endcase
end

// Ctrl bit 3 is tile code bit 8; only the 4K Swimmer planes are deep enough to use it
wire [11:0] bs_rom_addr = {swimmer & attr_big_sprite[3], bs_tile_code_r,
                           attr_big_sprite[5] ? ~y_line_bs[2:0] : y_line_bs[2:0]};

always_ff @(posedge clk) begin
    if (ce12) begin
        bs_ram_we <= 1'b0;
        if (x_pixel == 3'b000) begin
            bs_ram_addr <= xy_big_sprite;
            bs_vis_addr <= ~x_bs_cnt[7];
            if (ena_pixel) begin
                bs_tile_code <= bs_ram_do;
                bs_vis_code  <= bs_vis_addr;
            end
        end else begin
            bs_ram_addr <= cpu_addr[7:0];
            bs_ram_we   <= mem_wr & bsram_cs;
        end
    end
end

spram #(.DATA_WIDTH(8), .ADDR_WIDTH(8)) bs_ram
(
    .clk(clk),
    .addr(bs_ram_addr),
    .data(cpu_do),
    .q(bs_ram_do),
    .we(bs_ram_we)
);

always_ff @(posedge clk) begin
    if (ce12) begin
        if (ena_pixel)
            x_bs_cnt <= x_bs_cnt + 8'd1;
        if (is_sprite && sprite == 3'b110 && ena_pixel)
            x_bs_cnt <= 8'd120 + (x_big_sprite & 8'hF8);

        if (x_bs_cnt[2:0] == 3'b111 && ena_pixel) begin
            bs_tile_code_r <= bs_tile_code;
            bs_vis_r       <= bs_vis_code;
            bs_vis_g       <= bs_vis_r;
            bs_graph1      <= attr_big_sprite[4] ? bs_rom0_do : bitrev8(bs_rom0_do);
            bs_graph2      <= attr_big_sprite[4] ? bs_rom1_do : bitrev8(bs_rom1_do);
            bs_graph3      <= attr_big_sprite[4] ? bs_rom2_do : bitrev8(bs_rom2_do);
        end
    end
end

dpram_dc #(.widthad_a(12)) bs_rom0
(
    .clock_a(clk),
    .address_a(dl_bs_addr),
    .data_a(ioctl_dout),
    .wren_a(dl_bs0),

    .clock_b(clk),
    .address_b(bs_rom_addr),
    .q_b(bs_rom0_do)
);

dpram_dc #(.widthad_a(12)) bs_rom1
(
    .clock_a(clk),
    .address_a(dl_bs_addr),
    .data_a(ioctl_dout),
    .wren_a(dl_bs1),

    .clock_b(clk),
    .address_b(bs_rom_addr),
    .q_b(bs_rom1_do)
);

dpram_dc #(.widthad_a(12)) bs_rom2
(
    .clock_a(clk),
    .address_a(dl_bs_addr),
    .data_a(ioctl_dout),
    .wren_a(dl_bs2),

    .clock_b(clk),
    .address_b(bs_rom_addr),
    .q_b(bs_rom2_do)
);

always_ff @(posedge clk) begin
    if (ce_px) begin
        bs_graph1_d <= {bs_graph1_d[6:0], bs_graph1[x_bs_cnt[2:0]]};
        bs_graph2_d <= {bs_graph2_d[6:0], bs_graph2[x_bs_cnt[2:0]]};
        bs_graph3_d <= {bs_graph3_d[6:0], bs_graph3[x_bs_cnt[2:0]]};
        bs_vis_d    <= {bs_vis_d[6:0], bs_vis_g};
    end
end

// Big sprite pen: CC {colour3, 2 bits} and Swimmer {colour2, 3 bits} index a 32-entry PROM;
// Au {colour3, 3 bits} indexes the palette RAM
wire [2:0] bs_sel = ~x_big_sprite[2:0];
wire [5:0] bs_pixel_color = swimmer ? {attr_big_sprite[2:0], bs_graph1_d[bs_sel], bs_graph2_d[bs_sel], bs_graph3_d[bs_sel]}
                                    : {1'b0, attr_big_sprite[2:0], bs_graph1_d[bs_sel], bs_graph2_d[bs_sel]};

reg [5:0] bs_pixel_color_r = 6'd0;
reg       bs_pixel_vis_r = 1'b0;
reg       is_big_sprite_on = 1'b0;

always_ff @(posedge clk) begin
    if (ce12) begin
        bs_pixel_color_r <= bs_pixel_color;
        bs_pixel_vis_r   <= bs_vis_d[bs_sel];
        is_big_sprite_on <= pix_on(swimmer, {2'b00, bs_pixel_color_r}) && y_line_bs[7] && bs_pixel_vis_r;
    end
end

//------------------------------------------------------- Palette PROMs -------------------------------------------------------//

reg [7:0] pal    [64];      // CC: two 32x8 PROMs
reg [3:0] pal_lo [256];     // Swimmer: 256x4 PROM, R2..R0 + G0
reg [3:0] pal_hi [256];     // Swimmer: 256x4 PROM, B2..B1 + G2..G1
reg [7:0] bspal  [32];      // big sprite PROM, both boards

always_ff @(posedge clk) begin
    if (dl_pal)    pal[ioctl_addr[5:0]]    <= ioctl_dout;
    if (dl_pal_lo) pal_lo[ioctl_addr[7:0]] <= ioctl_dout[3:0];
    if (dl_pal_hi) pal_hi[ioctl_addr[7:0]] <= ioctl_dout[3:0];
    if (dl_bspal)  bspal[ioctl_addr[4:0]]  <= ioctl_dout;
end

reg [7:0] do_palette = 8'd0, do_bs_palette = 8'd0;
reg [3:0] do_pal_lo = 4'd0, do_pal_hi = 4'd0;
reg [7:0] do_au_b = 8'd0, do_au_gr = 8'd0, do_aubs_b = 8'd0, do_aubs_gr = 8'd0;

// Au: 64 pens; empty playfield pixels show pen 0
wire [5:0] au_pen = pf_clear_r ? 6'd0 : pixel_color_r[5:0];

always_ff @(posedge clk) begin
    if (ce12) begin
        do_palette    <= pal[pixel_color_r[5:0]];
        do_pal_lo     <= pal_lo[pixel_color_r];
        do_pal_hi     <= pal_hi[pixel_color_r];
        do_bs_palette <= bspal[bs_pixel_color_r[4:0]];
        do_au_b       <= aupal_b[au_pen];
        do_au_gr      <= aupal_gr[au_pen];
        do_aubs_b     <= aupal_b[bs_pixel_color_r];
        do_aubs_gr    <= aupal_gr[bs_pixel_color_r];
    end
end

//------------------------------------------------------- Colour output -------------------------------------------------------//

// CC resistor DAC: R/G 1K/470/220, B 470/220 (MAME compute_resistor_weights)
function automatic [7:0] cc_dac3(input [2:0] v);
    case (v)
        3'd0: cc_dac3 = 8'd0;   3'd1: cc_dac3 = 8'd33;  3'd2: cc_dac3 = 8'd71;  3'd3: cc_dac3 = 8'd104;
        3'd4: cc_dac3 = 8'd151; 3'd5: cc_dac3 = 8'd184; 3'd6: cc_dac3 = 8'd222; 3'd7: cc_dac3 = 8'd255;
    endcase
endfunction

function automatic [7:0] cc_dac2(input [1:0] v);
    case (v)
        2'd0: cc_dac2 = 8'd0; 2'd1: cc_dac2 = 8'd81; 2'd2: cc_dac2 = 8'd174; 2'd3: cc_dac2 = 8'd255;
    endcase
endfunction

// Swimmer levels are binary weighted 0x20/0x40/0x80 (MAME swimmer_palette)
function automatic [23:0] cc_rgb(input [7:0] p);
    cc_rgb = {cc_dac3(p[2:0]), cc_dac3(p[5:3]), cc_dac2(p[7:6])};
endfunction

function automatic [23:0] sw_rgb(input [7:0] p);
    sw_rgb = {p[2:0], 5'd0, p[5:3], 5'd0, p[7:6], 6'd0};
endfunction

// Au xBGR_333: MAME pal3bit expansion
function automatic [7:0] pal3(input [2:0] v);
    pal3 = {v, v, v[2:1]};
endfunction

function automatic [23:0] au_rgb(input [7:0] b, input [7:0] gr);
    au_rgb = {pal3(gr[2:0]), pal3(gr[6:4]), pal3(b[2:0])};
endfunction

wire [23:0] pf_rgb = au      ? au_rgb(do_au_b, do_au_gr) :
                     swimmer ? {do_pal_lo[2:0], 5'd0, do_pal_hi[1:0], do_pal_lo[3], 5'd0, do_pal_hi[3:2], 6'd0}
                             : cc_rgb(do_palette);
wire [23:0] bs_rgb = au      ? au_rgb(do_aubs_b, do_aubs_gr) :
                     swimmer ? sw_rgb(do_bs_palette) : cc_rgb(do_bs_palette);

// Swimmer empty pixels: background register, or the fixed side panel colour right of column 24
wire [23:0] bg_rgb   = {bgcolor[7:6], 6'd0, bgcolor[5:3], 5'd0, bgcolor[2:0], 5'd0};
wire [23:0] side_rgb = 24'h209879;

reg  [8:0] screen_x = 9'd0;
reg        pf_clear_d = 1'b1;
always_ff @(posedge clk) begin
    if (ce12) pf_clear_d <= pf_clear_r;
    if (ce_px) screen_x <= video_hblank ? 9'd0 : screen_x + 9'd1;
end

wire side_area = sidebg_en & (hinv ? (screen_x < 9'd64) : (screen_x >= 9'd192));

reg [23:0] video_mux;
always_comb begin
    if (is_big_sprite_on && !(bs_prio && sprite_on_r))
        video_mux = bs_rgb;
    else if (swimmer && !au && pf_clear_d)
        video_mux = side_area ? side_rgb : bg_rgb;
    else
        video_mux = pf_rgb;
end

reg [23:0] video_i = 24'd0;
always_ff @(posedge clk) begin
    if (ce_px)
        video_i <= video_hblank ? 24'd0 : video_mux;
end

assign {video_r, video_g, video_b} = video_i;

//------------------------------------------------------- Sound ---------------------------------------------------------------//

wire io_wr = ~cpu_iorq_n & ~cpu_wr_n & cpu_m1_n;
wire io_rd = ~cpu_iorq_n & ~cpu_rd_n & cpu_m1_n;

// CC I/O 08 = AY address, 09 = AY data, 0C = AY read
wire ay_bdir = ~swimmer & io_wr & (cpu_addr[7:1] == 7'b0000_100);
wire ay_bc1  = ~swimmer & ((io_wr & (cpu_addr[7:0] == 8'h08)) | (io_rd & (cpu_addr[7:0] == 8'h0C)));

wire signed [15:0] cc_audio, sw_audio;

cclimber_snd snd
(
    .clk(clk),
    .reset(reset | swimmer),

    .ay_bdir(ay_bdir),
    .ay_bc1(ay_bc1),
    .ay_din(cpu_do),
    .ay_dout(ay_dout),

    .rate_we(ce12 & a800_we & ~swimmer),
    .vol_we(ce12 & b000_we & ~swimmer),
    .cpu_do(cpu_do),
    .trigger(mainlatch[4] & ~swimmer),
    .vol5_en(vol5_en),

    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .smp_wr(dl_smp),

    .audio(cc_audio)
);

// Sound latch is clocked on the rising edge of /WRS at the end of the main CPU write
reg a800_we_d = 1'b0;
always_ff @(posedge clk) a800_we_d <= a800_we;

swimmer_snd snd_sw
(
    .clk(clk),
    .reset(reset | ~swimmer),
    .pause(pause),
    .au(au),
    .vblank(video_vblank),

    .latch_we(swimmer & a800_we_d & ~a800_we),
    .latch_din(cpu_do),

    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .rom_wr(dl_snd),

    .audio(sw_audio)
);

assign audio = swimmer ? sw_audio : cc_audio;

endmodule
