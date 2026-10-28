//============================================================================
//  board_template.sv - start a new Crazy Climber-core board by copying this file (NOT in files.qip, never compiled).
//  Copyright (C) 2026 Rodimus
//
//  Boards never instantiate a CPU, sound chip, ROM store or board RAM. They live ONCE in the dispatcher
//  rtl/cclimber_dispatcher.sv: Z80s z80_0 (main) / z80_1 (sound), AY-3-8910s aysel_0-1, TMS5110 tms_0 (chip_pool_pkg buses),
//  the ROM blocks (program, tiles, big sprite, sound program, samples, speech, gradient, Top Roller planes; loaded by
//  ioctl index + address through rtl/ram_rom/rom_loader.sv) and the board RAM pool: dual-port blocks pr 0-6
//  (4K, 2K, 1K, 256, 1K, 1K, 512) and single-port spram blocks sp 0-3 (1K, 256, 256, 1K; port A of pram_i_t).
//  To add a board: copy this file to rtl/boards/<board>/<board>.sv, add it to files.qip + verilator/Makefile,
//  instance it from rtl/boards/cclimber/cclimber_main.sv (or the dispatcher), put its buses on the muxes there
//  (z80_1_i / aysel_i / sp_i[3] are picked by the board flags) and tie what it doesn't use to '0. A RAM bigger than
//  its block = grow the block, never a private dpram_dc / spram. ROM images: load decode by ioctl index and address
//  only, NEVER by a game flag. A RAM / chip that truly can't pool = "// POOL-EXCEPTION: <reason>" on its instance
//  line + a Pool contract row (Claude/ vault note). verilator/common/pool_check.sh (POOL_MODS) enforces it.
//============================================================================

module board_template
(
    input  logic        clk,            // 49.152 MHz
    input  logic        reset,          // core reset | this board inactive
    input  logic        pause,

    output chip_pool_pkg::z80_i_t         z80_1_i,
    input  chip_pool_pkg::z80_o_t         z80_1_o,
    output chip_pool_pkg::aysel_i_t [1:0] aysel_i,
    input  chip_pool_pkg::aysel_o_t [1:0] aysel_o,

    output logic [12:0] rom0_a,         // sound program ROM block read port
    input  logic  [7:0] rom0_d,

    output ram_pool_pkg::pram_i_t         pr_i,   // pool block sp 3 (port A)
    input  ram_pool_pkg::pram_o_t         pr_o,

    output logic signed [15:0] audio
);

assign z80_1_i = '0;
assign aysel_i = '0;
assign rom0_a  = 13'd0;
assign pr_i    = '0;
assign audio   = 16'sd0;

endmodule
