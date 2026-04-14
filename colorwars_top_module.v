`timescale 1ns / 1ps

// Color Wars top-level module
//
// Wires together the game FSM (control) and datapath (cell array + logic).
//
// Physical I/O:
//   Inputs:  two-phase clocks, reset, 5-bit one-hot row & column, confirm button
//   Outputs: error LEDs, player indicator, game state, 75-bit cell states for
//            LED matrix display, game-over flag, winning player
//
// The 75-bit all_cell_states bus carries every cell's 3-bit state:
//   cell (r, c) = all_cell_states[ 3*(r*5+c) +: 3 ]
//   Encoding: 000=EMPTY, 010=P1_age1, 100=P1_age2, 110=P1_age3,
//             011=P2_age1, 101=P2_age2, 111=P2_age3, 001=EXP

module colorwars_top (
    input  wire        clka,
    input  wire        clkb,
    input  wire        reset,

    // Player controls
    input  wire [4:0]  row,
    input  wire [4:0]  column,
    input  wire        confirm,

    // Error indicators (active for one cycle on bad input)
    output wire        show_empty_error,
    output wire        show_owner_error,
    output wire        show_row_col_error,
    output wire        show_multi_error,

    // Game status
    output wire [2:0]  state,               // FSM state (debug)
    output wire        player_reg,          // whose turn: 0=P1, 1=P2
    output wire        first_turn,          // high during first round
    output wire        game_over,           // high when someone has won
    output wire        winner_player,       // 0=P1 won, 1=P2 won

    // Cell display data (directly drives LED matrix)
    output wire [74:0] all_cell_states
);

    // ---------------------------------------------------------------
    // Internal wires: FSM <-> Datapath
    // ---------------------------------------------------------------

    // FSM -> Datapath
    wire start_iteration;
    wire change_player;

    // Datapath -> FSM  (error flags)
    wire cell_is_empty_error;
    wire cell_is_other_player_error;
    wire empty_row_or_col_error;
    wire multiple_inputs_error;

    // Datapath -> FSM  (board status)
    wire any_exploding;
    wire have_a_winner;

    // ---------------------------------------------------------------
    // FSM instance
    // ---------------------------------------------------------------
    colorwars_fsm fsm (
        .clk_a_in                    (clka),
        .reset_in                    (reset),

        // Player inputs
        .row_in                      (row),
        .column_in                   (column),
        .confirm_in                  (confirm),

        // Error flags from datapath
        .cell_is_empty_error_in      (cell_is_empty_error),
        .cell_is_other_player_error_in (cell_is_other_player_error),
        .empty_row_or_col_error_in   (empty_row_or_col_error),
        .multiple_inputs_error_in    (multiple_inputs_error),

        // Board status from datapath
        .any_exploding_in            (any_exploding),
        .have_a_winner_in            (have_a_winner),

        // Control signals to datapath
        .start_iteration_out         (start_iteration),
        .change_player_out           (change_player),

        // Error display outputs
        .show_empty_error_out        (show_empty_error),
        .show_owner_error_out        (show_owner_error),
        .show_row_col_error_out      (show_row_col_error),
        .show_multi_error_out        (show_multi_error),

        // Game status
        .game_over_out               (game_over),
        .state_out                   (state)
    );

    // ---------------------------------------------------------------
    // Datapath instance
    // ---------------------------------------------------------------
    colorwars_dp dp (
        .clka_in                     (clka),
        .clkb_in                     (clkb),
        .reset_in                    (reset),

        // Player inputs (for decoding and validation)
        .row_in                      (row),
        .column_in                   (column),

        // Control signals from FSM
        .start_iteration_in          (start_iteration),
        .change_player_in            (change_player),

        // Error flags to FSM
        .cell_is_empty_error_out     (cell_is_empty_error),
        .cell_is_other_player_error_out (cell_is_other_player_error),
        .empty_row_or_col_error_out  (empty_row_or_col_error),
        .multiple_inputs_error_out   (multiple_inputs_error),

        // Board status to FSM
        .any_exploding_out           (any_exploding),
        .have_a_winner_out           (have_a_winner),

        // External outputs
        .player_reg_out              (player_reg),
        .first_turn_out              (first_turn),
        .winner_player_out           (winner_player),
        .all_cell_states_out         (all_cell_states)
    );

endmodule
