//============================================================================
//
//  Top Roller (Jaleco 8307-B) video: 56-sprite line engine + scrolling background
//  Copyright (C) 2026 Rodimus
//
//  BEST EFFORT WITHOUT SCHEMATICS AVAILABLE. Behaviour per MAME cclimber.cpp
//  (Nicola Salmoria); the 256x2 PROM at S9 is not emulated, as in MAME.
//
//============================================================================

module toprollr_video
#(
    parameter [7:0] X_START = 8'd0,     // MAME x of the first displayed pixel of a line
    parameter [7:0] Y_OFS   = 8'd1      // MAME y rendered = displayed line + Y_OFS
)
(
    input               clk,            // 49.152 MHz
    input               ce_px,
    input               hblank,
    input         [7:0] line_y,         // raw V counter of the line being displayed
    input               flip_x,         // effective flips (game latch ^ CRT flip)
    input               flip_y,

    // CPU: sprite RAM 9880-995F, bg video RAM 8C00-8FFF, bg colour RAM 9400-97FF
    input        [15:0] cpu_addr,
    input         [7:0] cpu_do,
    input               cpu_wr,
    output reg    [7:0] cpu_di,
    output              cpu_sel,

    // ROM loading (ioctl index 7)
    input        [24:0] ioctl_addr,
    input         [7:0] ioctl_dout,
    input               dl_tile0,
    input               dl_tile1,
    input               dl_bg0,
    input               dl_bg1,

    output reg    [5:0] spr_pen = 6'd0,  // {colour, pixel}; pen = 0x00 + this
    output reg          spr_on = 1'b0,
    output reg    [5:0] bg_pen = 6'd0,   // {colour, pixel}; pen = 0x60 + this
    output reg          in_clip = 1'b0
);

//------------------------------------------------------- CPU-side RAMs -------------------------------------------------------//

wire spr_cs = (cpu_addr >= 16'h9880) && (cpu_addr < 16'h9960);
wire bgv_cs = cpu_addr[15:10] == 6'b100011;        // 8C00-8FFF
wire bgc_cs = cpu_addr[15:10] == 6'b100101;        // 9400-97FF
assign cpu_sel = spr_cs | bgv_cs | bgc_cs;

wire [7:0] spr_addr_cpu = cpu_addr[7:0] - 8'h80;
wire [7:0] spr_q_cpu, bgv_q_cpu, bgc_q_cpu;
wire [7:0] spr_q, bgv_q, bgc_q;
reg  [7:0] spr_rd_addr = 8'd0;
reg  [9:0] bg_ram_addr = 10'd0;

dpram_dc #(.widthad_a(8)) spriteram
(
    .clock_a(clk), .address_a(spr_addr_cpu), .data_a(cpu_do), .wren_a(cpu_wr & spr_cs), .q_a(spr_q_cpu),
    .clock_b(clk), .address_b(spr_rd_addr), .q_b(spr_q)
);

dpram_dc #(.widthad_a(10)) bg_vram
(
    .clock_a(clk), .address_a(cpu_addr[9:0]), .data_a(cpu_do), .wren_a(cpu_wr & bgv_cs), .q_a(bgv_q_cpu),
    .clock_b(clk), .address_b(bg_ram_addr), .q_b(bgv_q)
);

dpram_dc #(.widthad_a(10)) bg_cram
(
    .clock_a(clk), .address_a(cpu_addr[9:0]), .data_a(cpu_do), .wren_a(cpu_wr & bgc_cs), .q_a(bgc_q_cpu),
    .clock_b(clk), .address_b(bg_ram_addr), .q_b(bgc_q)
);

always_comb begin
    if (spr_cs)      cpu_di = spr_q_cpu;
    else if (bgv_cs) cpu_di = bgv_q_cpu;
    else             cpu_di = bgc_q_cpu;
end

// bg_vram[0] is the whole-layer X scroll
reg [7:0] bg_scroll = 8'd0;
always_ff @(posedge clk) if (cpu_wr && bgv_cs && cpu_addr[9:0] == 10'd0) bg_scroll <= cpu_do;

//------------------------------------------------------- Graphics ROMs -------------------------------------------------------//

// Sprite planes: a private copy of the "tile" region (MSB plane first), so the engine never contends with the playfield
reg  [12:0] spr_rom_addr = 13'd0;
wire  [7:0] spr_p0, spr_p1;

dpram_dc #(.widthad_a(13)) spr_rom0
(
    .clock_a(clk), .address_a(ioctl_addr[12:0]), .data_a(ioctl_dout), .wren_a(dl_tile0),
    .clock_b(clk), .address_b(spr_rom_addr), .q_b(spr_p0)
);

dpram_dc #(.widthad_a(13)) spr_rom1
(
    .clock_a(clk), .address_a(ioctl_addr[12:0]), .data_a(ioctl_dout), .wren_a(dl_tile1),
    .clock_b(clk), .address_b(spr_rom_addr), .q_b(spr_p1)
);

// Background planes: "gfx3", 2 x 4K, 512 characters
reg  [11:0] bg_rom_addr = 12'd0;
wire  [7:0] bg_p0, bg_p1;

dpram_dc #(.widthad_a(12)) bg_rom0
(
    .clock_a(clk), .address_a(ioctl_addr[11:0]), .data_a(ioctl_dout), .wren_a(dl_bg0),
    .clock_b(clk), .address_b(bg_rom_addr), .q_b(bg_p0)
);

dpram_dc #(.widthad_a(12)) bg_rom1
(
    .clock_a(clk), .address_a(ioctl_addr[11:0]), .data_a(ioctl_dout), .wren_a(dl_bg1),
    .clock_b(clk), .address_b(bg_rom_addr), .q_b(bg_p1)
);

//------------------------------------------------------- Line timing ---------------------------------------------------------//

reg       hblank_d = 1'b1;
reg       line_start = 1'b0;
reg [7:0] cur_y = 8'd0;
reg [7:0] mx = 8'd0;                       // MAME x being computed for the next output
reg [2:0] ph = 3'd0;                        // clock phase since ce_px

always_ff @(posedge clk) begin
    hblank_d   <= hblank;
    line_start <= hblank_d & ~hblank;
    if (hblank_d & ~hblank) cur_y <= line_y;

    ph <= ce_px ? 3'd0 : (ph == 3'd7 ? ph : ph + 3'd1);
    if (ce_px) mx <= hblank ? X_START : mx + 8'd1;
end

//------------------------------------------------------- Sprite line buffer (ping-pong) --------------------------------------//

reg        wsel = 1'b0;
reg  [8:0] lb_waddr = 9'd0;
reg  [7:0] lb_wdata = 8'd0;
reg        lb_we = 1'b0;
wire [7:0] lb_q;

dpram_dc #(.widthad_a(9)) linebuf
(
    .clock_a(clk), .address_a(lb_waddr), .data_a(lb_wdata), .wren_a(lb_we),
    .clock_b(clk), .address_b({~wsel, mx}), .q_b(lb_q)
);

//------------------------------------------------------- Sprite engine -------------------------------------------------------//

localparam S_IDLE = 3'd0, S_CLEAR = 3'd1, S_READ = 3'd2, S_CHECK = 3'd3, S_FETCH = 3'd4, S_DRAW = 3'd5;

reg  [2:0] st = S_IDLE;
reg  [7:0] ey = 8'd0;                       // MAME line being drawn
reg  [7:0] cx = 8'd0;
reg  [5:0] sn = 6'd0;                       // sprite number, 55 down to 0
reg  [2:0] rk = 3'd0;                       // sprite byte read step
reg  [7:0] a0 = 8'd0, a1 = 8'd0, sy_raw = 8'd0, sx_raw = 8'd0;
reg  [7:0] sx = 8'd0;
reg  [3:0] gy = 4'd0;
reg        fx = 1'b0;
reg        half = 1'b0;
reg  [1:0] fw = 2'd0;                       // ROM fetch wait
reg  [2:0] pi = 3'd0;                       // pixel within half
reg  [7:0] d0 = 8'd0, d1 = 8'd0;

// MAME toprollr_draw_sprites: x = spr[3], y = 240 - spr[2]; flip screen mirrors both and inverts the flips
wire [7:0] m_x    = flip_x ? (8'd240 - sx_raw) : sx_raw;
wire [7:0] m_y0   = 8'd240 - sy_raw;
wire [7:0] m_y    = flip_y ? (8'd240 - m_y0) : m_y0;
wire       m_fx   = a0[6] ^ flip_x;
wire       m_fy   = a0[7] ^ flip_y;
wire [7:0] m_row  = ey - m_y;
wire [7:0] code   = {a1[4], a1[5], a0[5:0]};

wire [2:0] bit_sel = fx ? pi : (3'd7 - pi);
wire [1:0] pix     = {d0[bit_sel], d1[bit_sel]};
wire [8:0] px_x    = {1'b0, sx} + {5'd0, half, pi};

always_ff @(posedge clk) begin
    lb_we <= 1'b0;

    if (line_start) begin
        wsel <= ~wsel;
        ey   <= line_y + Y_OFS;
        cx   <= 8'd0;
        st   <= S_CLEAR;
    end else case (st)
        S_CLEAR: begin
            lb_waddr <= {wsel, cx};
            lb_wdata <= 8'd0;
            lb_we    <= 1'b1;
            cx       <= cx + 8'd1;
            if (cx == 8'd255) begin
                sn <= 6'd55;
                rk <= 3'd0;
                st <= S_READ;
            end
        end

        // Four byte reads: address at step k, data one clock later
        S_READ: begin
            rk <= rk + 3'd1;
            spr_rd_addr <= {sn, rk[1:0]};
            case (rk)
                3'd2: a0     <= spr_q;
                3'd3: a1     <= spr_q;
                3'd4: sy_raw <= spr_q;
                3'd5: begin sx_raw <= spr_q; st <= S_CHECK; end
                default: ;
            endcase
        end

        S_CHECK: begin
            if (m_row < 8'd16) begin
                sx   <= m_x;
                fx   <= m_fx;
                gy   <= m_fy ? (4'd15 - m_row[3:0]) : m_row[3:0];
                half <= 1'b0;
                fw   <= 2'd0;
                st   <= S_FETCH;
            end else if (sn == 6'd0)
                st <= S_IDLE;
            else begin
                sn <= sn - 6'd1;
                rk <= 3'd0;
                st <= S_READ;
            end
        end

        // byte = code*32 + (gy>=8 ? 16 : 0) + (column half ? 8 : 0) + (gy & 7); the drawn half flips with X
        S_FETCH: begin
            spr_rom_addr <= {code, gy[3], half ^ fx, gy[2:0]};
            fw <= fw + 2'd1;
            if (fw == 2'd2) begin
                d0 <= spr_p0;
                d1 <= spr_p1;
                pi <= 3'd0;
                st <= S_DRAW;
            end
        end

        S_DRAW: begin
            if (pix != 2'b00 && !px_x[8]) begin
                lb_waddr <= {wsel, px_x[7:0]};
                lb_wdata <= {2'b10, a1[3:0], pix};
                lb_we    <= 1'b1;
            end
            pi <= pi + 3'd1;
            if (pi == 3'd7) begin
                if (!half) begin
                    half <= 1'b1;
                    fw   <= 2'd0;
                    st   <= S_FETCH;
                end else if (sn == 6'd0)
                    st <= S_IDLE;
                else begin
                    sn <= sn - 6'd1;
                    rk <= 3'd0;
                    st <= S_READ;
                end
            end
        end

        default: ;
    endcase
end

//------------------------------------------------------- Background layer ----------------------------------------------------//

// MAME toproller_get_bg_tile_info: code {col[6], vram}, colour col[3:0], TILE_FLIPX; one X scroll for the layer
wire [7:0] bx = (flip_x ? ~mx : mx) + bg_scroll;
wire [7:0] by = flip_y ? ~cur_y : cur_y;
reg  [7:0] bx_r = 8'd0;
reg  [3:0] bg_col_r = 4'd0;
reg  [5:0] bg_res = 6'd0;

always_ff @(posedge clk) begin
    case (ph)
        3'd0: begin
            bx_r        <= bx;
            bg_ram_addr <= {by[7:3], bx[7:3]};
        end
        3'd2: begin
            bg_rom_addr <= {bgc_q[6], bgv_q, by[2:0]};
            bg_col_r    <= bgc_q[3:0];
        end
        3'd4: bg_res <= {bg_col_r, bg_p0[bx_r[2:0]], bg_p1[bx_r[2:0]]};
        default: ;
    endcase
end

//------------------------------------------------------- Output ---------------------------------------------------------------//

// MAME clips background and sprites to x 40..231 (24..215 when flipped); the playfield is not clipped
always_ff @(posedge clk) begin
    if (ce_px) begin
        spr_on  <= lb_q[7];
        spr_pen <= lb_q[5:0];
        bg_pen  <= bg_res;
        in_clip <= flip_x ? (mx >= 8'd24 && mx <= 8'd215) : (mx >= 8'd40 && mx <= 8'd231);
    end
end

endmodule
