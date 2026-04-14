`timescale 1ns / 1ps

// Main game controller FSM for Color Wars
//
// Turn flow:
//   IDLE -> INPUT_VERIFICATION -> ITERATE_THROUGH_CELLS -> IDLE (or GAME_END)
//
// The datapath computes all input validation errors combinationally.
// The FSM checks them in INPUT_VERIFICATION and routes accordingly.
//
// During ITERATE_THROUGH_CELLS, the parallel cell array resolves one
// "layer" of explosions per clock cycle. The FSM stays in this state
// until any_exploding_in goes low (board is stable), then either
// declares a winner or returns to IDLE for the next player's turn.

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

    // ---------------------------------------------------------------
    // State encoding
    // ---------------------------------------------------------------
    localparam IDLE                  = 3'd0;
    localparam INPUT_VERIFICATION    = 3'd1;
    localparam ITERATE_THROUGH_CELLS = 3'd2;
    localparam GAME_END              = 3'd3;
    localparam RESET_STATE           = 3'd4;

    reg [2:0] next_state;

    // ---------------------------------------------------------------
    // Logic to calculate to get posedge of confirm_in
    // ---------------------------------------------------------------
    reg confirm_prev;
    always @(negedge clk_a_in) begin
        if (reset_in)
            confirm_prev <= 1'b0;
        else
            confirm_prev <= confirm_in;
    end

    wire confirm_rising = confirm_in & ~confirm_prev; // if past was 0 but now it's 1, then its the posedge!

    // ---------------------------------------------------------------
    // State register (negedge clk_a, async reset)
    // ---------------------------------------------------------------
    always @(negedge clk_a_in) begin
        if (reset_in)
            state_out <= RESET_STATE;
        else
            state_out <= next_state;
    end

    // ---------------------------------------------------------------
    // Next-state and output logic (combinational)
    // ---------------------------------------------------------------
    always @(*) begin
        // Defaults: all outputs low, hold state
        next_state            = state_out;
        start_iteration_out   = 1'b0;
        change_player_out     = 1'b0;
        show_empty_error_out  = 1'b0;
        show_owner_error_out  = 1'b0;
        show_row_col_error_out = 1'b0;
        show_multi_error_out  = 1'b0;
        game_over_out         = 1'b0;

        case (state_out)
            // ---------------------------------------------------------
            IDLE: begin
                // Wait for player to select a cell and press confirm.
                // Basic sanity: row and column must be non-zero.
                if (confirm_rising) // before I had  && row_in != 5'd0 && column_in != 5'd0, but wanted to have input_verification check
                    next_state = INPUT_VERIFICATION;
            end

            // ---------------------------------------------------------
            INPUT_VERIFICATION: begin
                // Check errors in priority order.  The datapath computes
                // all of these combinationally from row/col/cell state.
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
                    // Move is valid — tell the datapath to apply it.
                    // age_change_enable will be pulsed on the selected cell.
                    start_iteration_out = 1'b1;
                    next_state = ITERATE_THROUGH_CELLS;
                end
            end

            // ---------------------------------------------------------
            ITERATE_THROUGH_CELLS: begin
                // Stay here while any cell is exploding (chain reactions).
                // Each clka/clkb cycle resolves one layer of explosions.
                if (!any_exploding_in) begin
                    // Board is stable.
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

            // ---------------------------------------------------------
            GAME_END: begin
                game_over_out = 1'b1;
                next_state    = GAME_END;  // frozen until reset
            end

            // ---------------------------------------------------------
            RESET_STATE: begin
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

endmodule
