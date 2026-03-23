`timescale 1ns / 1ps

// Main game controller FSM for Color Wars
// Handles turn flow: validates player input, triggers cell updates,
// and manages chain reactions from explosions.

module game_fsm (
    input  wire        clk_a,
    input  wire        reset,               // async reset, active-high

    // Player inputs (active when buttons pressed)
    input  wire        win_register,        // game over flag from datapath
    input  wire [4:0]  row,                 // one-hot row selection
    input  wire [4:0]  column,              // one-hot column selection
    input  wire        confirm,             // player confirms their move

    // Feedback from datapath about current board state
    input  wire        cell_is_empty,       // selected cell has no owner
    input  wire        cell_is_other_player,// selected cell belongs to opponent
    input  wire        explode_flag,        // at least one cell exploded this pass
    input  wire        first_turn_flag,     // true until first valid move is made
    input  wire        iterate_done,        // finished scanning all cells

    // Control signals sent to datapath
    output reg         start_iteration,     // kick off cell update scan
    output reg         clear_errors,        // clear previous error displays
    output reg         show_empty_error,    // can't select empty cell (after first turn)
    output reg         show_owner_error,    // can't select opponent's cell
    output reg         multiple_inputs_error,// pressed multiple rows or columns

    output reg [2:0]   state                // current state (useful for debugging)
);

    // FSM states
    localparam IDLE                  = 3'd0;  // waiting for player input
    localparam INPUT_VERIFICATION    = 3'd1;  // checking if move is legal
    localparam ITERATE_THROUGH_CELLS = 3'd2;  // updating cells, handling explosions
    localparam GAME_END              = 3'd3;  // someone won, game frozen
    localparam RESET_STATE           = 3'd4;  // initial state after reset

    reg [2:0] next_state;

    // Detect if player pressed more than one button in a row or column
    // (one-hot should have at most one bit set, so x & (x-1) should be 0)
    wire multiple_rows_pressed    = (row & (row - 1)) != 0;
    wire multiple_columns_pressed = (column & (column - 1)) != 0;
    wire multiple_inputs_pressed  = multiple_rows_pressed || multiple_columns_pressed;

    // State register with async reset
    always @(negedge clk_a or posedge reset) begin
        if (reset)
            state <= RESET_STATE;
        else
            state <= next_state;
    end

    // Combinational logic for next state and outputs
    always @(*) begin
        next_state            = state;
        start_iteration       = 1'b0;
        clear_errors          = 1'b0;
        show_empty_error      = 1'b0;
        show_owner_error      = 1'b0;
        multiple_inputs_error = 1'b0;

        case (state)

            IDLE: begin
                // Check for game over first
                if (win_register)
                    next_state = GAME_END;
                // Wait for player to select a cell and confirm
                else if (row != 5'd0 && column != 5'd0 && confirm)
                    next_state = INPUT_VERIFICATION;
            end

            INPUT_VERIFICATION: begin
                clear_errors = 1'b1;
                
                // Reject invalid inputs and show appropriate error
                if (multiple_inputs_pressed) begin 
                    multiple_inputs_error = 1'b1; 
                    next_state = IDLE; 
                end 
                else if (cell_is_empty && first_turn_flag) begin
                    // After first turn, can't click empty cells
                    show_empty_error = 1'b1;
                    next_state = IDLE;
                end
                else if (cell_is_other_player) begin
                    // Can't click opponent's cells
                    show_owner_error = 1'b1;
                    next_state = IDLE;
                end
                else begin
                    // Move is valid, start processing cells
                    start_iteration = 1'b1;
                    next_state = ITERATE_THROUGH_CELLS;
                end
            end

            ITERATE_THROUGH_CELLS: begin
                // Keep iterating while explosions are happening (chain reactions)
                if (iterate_done) begin
                    if (explode_flag)
                        next_state = ITERATE_THROUGH_CELLS;  // more explosions, keep going
                    else
                        next_state = IDLE;  // board is stable, next player's turn
                end
            end

            GAME_END: begin
                // Stay here until reset
                next_state = GAME_END;
            end

            RESET_STATE: begin
                // Go to idle on the next clock
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

endmodule

