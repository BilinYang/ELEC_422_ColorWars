`timescale 1ns / 1ps

// Controller FSM for the Color Wars game.
//
// High-level flow:
//   IDLE -> INPUT_VERIFICATION -> ITERATE_THROUGH_CELLS -> IDLE (or GAME_END)
//
// The datapath continuously computes the “is this move valid?” flags.
// In INPUT_VERIFICATION we sample those flags and either reject the move
// (with a one-cycle error pulse) or kick off an iteration.
//
// While iterating, the board resolves one explosion wave per cycle. We sit in
// ITERATE_THROUGH_CELLS until the board is stable again, then either end the
// game or hand off to the other player.

module colorwars_fsm (
    input  wire       clk_a_in,
    input  wire       reset_in,

    // Player inputs
    input  wire [4:0] row_in,
    input  wire [4:0] column_in,
    input  wire       confirm_in,

    // Error flags from datapath (active during INPUT_VERIFICATION)
    input  wire       cell_is_empty_error_in,
    input  wire       cell_is_other_player_error_in,
    input  wire       empty_row_or_col_error_in,
    input  wire       multiple_inputs_error_in,

    // Board status from datapath
    input  wire       any_exploding_in,     // at least one cell is in EXP state
    input  wire       have_a_winner_in,     // all non-empty cells belong to one player

    // Control signals to datapath
    output reg        start_iteration_out,  // pulse: apply the player's move
    output reg        change_player_out,    // pulse: toggle player register

    // Error display outputs (active for one cycle on error)
    output reg        show_empty_error_out,
    output reg        show_owner_error_out,
    output reg        show_row_col_error_out,
    output reg        show_multi_error_out,

    // Game status
    output reg        game_over_out,        // high when in GAME_END state
    output reg  [2:0] state_out             // current FSM state (debug / external use)
);

    // State encoding (kept simple for debug).
    localparam IDLE                  = 3'd0;
    localparam INPUT_VERIFICATION    = 3'd1;
    localparam ITERATE_THROUGH_CELLS = 3'd2;
    localparam GAME_END              = 3'd3;
    localparam RESET_STATE           = 3'd4;

    reg [2:0] next_state;

    // State register (negedge clock, async reset).
    always @(negedge clk_a_in or posedge reset_in) begin
        if (reset_in)
            state_out <= RESET_STATE;
        else
            state_out <= next_state;
    end

    // Next-state + outputs (combinational).
    always @(*) begin
        // Default: hold state, pulse nothing.
        next_state            = state_out;
        start_iteration_out   = 1'b0;
        change_player_out     = 1'b0;
        show_empty_error_out  = 1'b0;
        show_owner_error_out  = 1'b0;
        show_row_col_error_out = 1'b0;
        show_multi_error_out  = 1'b0;
        game_over_out         = 1'b0;

        case (state_out)
            // State: IDLE
            IDLE: begin
                // Sit and wait for a confirm with non-zero row/col.
                if (confirm_in && row_in != 5'd0 && column_in != 5'd0)
                    next_state = INPUT_VERIFICATION;
            end

            // State: INPUT_VERIFICATION
            INPUT_VERIFICATION: begin
                // Check errors in priority order (all computed in the datapath).
                if (multiple_inputs_error_in) begin
                    show_multi_error_out = 1'b1;
                    next_state = IDLE;
                end
                else if (empty_row_or_col_error_in) begin
                    show_row_col_error_out = 1'b1;
                    next_state = IDLE;
                end
                else if (cell_is_empty_error_in) begin
                    show_empty_error_out = 1'b1;
                    next_state = IDLE;
                end
                else if (cell_is_other_player_error_in) begin
                    show_owner_error_out = 1'b1;
                    next_state = IDLE;
                end
                else begin
                    // Valid move: tell the datapath to apply it.
                    start_iteration_out = 1'b1;
                    next_state = ITERATE_THROUGH_CELLS;
                end
            end

            // State: ITERATE_THROUGH_CELLS
            ITERATE_THROUGH_CELLS: begin
                // Stay here while chain reactions are still happening.
                if (!any_exploding_in) begin
                    // Board is stable again.
                    if (have_a_winner_in) begin
                        next_state  = GAME_END;
                        game_over_out = 1'b1;
                    end
                    else begin
                        next_state        = IDLE;
                        change_player_out = 1'b1;
                    end
                end
                // else: stay in ITERATE_THROUGH_CELLS (default)
            end

            // State: GAME_END
            GAME_END: begin
                game_over_out = 1'b1;
                next_state    = GAME_END;  // stay here until reset
            end

            // State: RESET_STATE
            RESET_STATE: begin
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

endmodule
