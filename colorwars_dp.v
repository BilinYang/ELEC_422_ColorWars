`timescale 1ns / 1ps

// Color Wars datapath: the board, the decoding, and the “is this move legal?” logic.
//
// Big pieces in here:
//   - 25 cell_fsm instances arranged as a 5x5 grid
//   - row/column one-hot decoding
//   - move validation flags back to the controller FSM
//   - player tracking + first-round handling
//   - basic win detection
//
// Explosions are wired combinationally: a cell’s takeover_enable is just the OR
// of its four orthogonal neighbors being in EXP. Only one “wave” settles per
// clka/clkb cycle, so chain reactions naturally take multiple cycles.
//
// Indexing is row-major: idx = row*5 + col (0..24).

module colorwars_dp (
    input  wire       clka_in,
    input  wire       clkb_in,
    input  wire       reset_in,

    // Player button inputs (active during IDLE / INPUT_VERIFICATION)
    input  wire [4:0] row_in,               // one-hot row selection
    input  wire [4:0] column_in,            // one-hot column selection

    // Control signals from FSM
    input  wire       start_iteration_in,   // pulse: apply age_change to selected cell
    input  wire       change_player_in,     // pulse: toggle player register

    // Error flags to FSM (combinational, always valid)
    output wire       cell_is_empty_error_out,
    output wire       cell_is_other_player_error_out,
    output wire       empty_row_or_col_error_out,
    output wire       multiple_inputs_error_out,

    // Board status to FSM
    output wire       any_exploding_out,    // any cell in EXP state
    output wire       have_a_winner_out,    // one player owns all non-empty cells

    // External outputs
    output wire       player_reg_out,       // current player: 0=P1, 1=P2
    output wire       first_turn_out,       // high during the first round (2 moves)
    output wire       winner_player_out,    // which player won (valid when game_over)
    output wire [74:0] all_cell_states_out  // 25 cells x 3 bits, for LED display
);

    // State constants used for comparisons (must match cell_fsm).
    localparam EMPTY = 3'b000;
    localparam EXP   = 3'b001;

    // Player register + a tiny first-round counter.
    reg player_reg;
    reg [1:0] move_count;

    always @(negedge clka_in or posedge reset_in) begin
        if (reset_in)
            player_reg <= 1'b0;         // Player 1 goes first
        else if (change_player_in)
            player_reg <= ~player_reg;
    end

    always @(negedge clka_in or posedge reset_in) begin
        if (reset_in)
            move_count <= 2'd0;
        else if (change_player_in && move_count < 2'd2)
            move_count <= move_count + 2'd1;
    end

    wire first_turn = (move_count < 2'd2);

    assign player_reg_out  = player_reg;
    assign first_turn_out  = first_turn;

    // One-hot decode for row/column.
    reg [2:0] rowNum;
    reg [2:0] colNum;

    always @(*) begin
        case (row_in)
            5'b00001: rowNum = 3'd0;
            5'b00010: rowNum = 3'd1;
            5'b00100: rowNum = 3'd2;
            5'b01000: rowNum = 3'd3;
            5'b10000: rowNum = 3'd4;
            default:  rowNum = 3'd0;   // garbage if invalid, but errors catch it
        endcase
    end

    always @(*) begin
        case (column_in)
            5'b00001: colNum = 3'd0;
            5'b00010: colNum = 3'd1;
            5'b00100: colNum = 3'd2;
            5'b01000: colNum = 3'd3;
            5'b10000: colNum = 3'd4;
            default:  colNum = 3'd0;
        endcase
    end

    // Input validation (purely combinational).
    // More than one bit set in either group.
    wire multi_row = (row_in & (row_in - 5'd1)) != 5'd0;
    wire multi_col = (column_in & (column_in - 5'd1)) != 5'd0;
    assign multiple_inputs_error_out = multi_row || multi_col;

    // Missing a row or a column selection.
    assign empty_row_or_col_error_out = (row_in == 5'd0) || (column_in == 5'd0);

    // 25 cell instances + neighbor explosion wiring.
    wire [2:0] cs       [0:24];   // cell state outputs
    wire       age_en   [0:24];   // age_change_enable per cell
    wire       take_en  [0:24];   // takeover_enable per cell

    genvar r, c;
    generate
        for (r = 0; r < 5; r = r + 1) begin : row_gen
            for (c = 0; c < 5; c = c + 1) begin : col_gen

                localparam integer IDX = r * 5 + c;

                // Explosion propagation: look at the four neighbors.
                // Edges just treat the missing neighbor as 0.
                wire up_exp, down_exp, left_exp, right_exp;

                if (r > 0) begin : has_up
                    assign up_exp = (cs[IDX - 5] == EXP);
                end else begin : no_up
                    assign up_exp = 1'b0;
                end

                if (r < 4) begin : has_down
                    assign down_exp = (cs[IDX + 5] == EXP);
                end else begin : no_down
                    assign down_exp = 1'b0;
                end

                if (c > 0) begin : has_left
                    assign left_exp = (cs[IDX - 1] == EXP);
                end else begin : no_left
                    assign left_exp = 1'b0;
                end

                if (c < 4) begin : has_right
                    assign right_exp = (cs[IDX + 1] == EXP);
                end else begin : no_right
                    assign right_exp = 1'b0;
                end

                assign take_en[IDX] = up_exp | down_exp | left_exp | right_exp;

                // Only the selected cell gets an age-change pulse, and only when
                // the controller says to apply the move.
                assign age_en[IDX] = (r[2:0] == rowNum) && (c[2:0] == colNum)
                                     && start_iteration_in;

                // Cell instance.
                cell_fsm cell_inst (
                    .clka_in              (clka_in),
                    .clkb_in              (clkb_in),
                    .reset_in             (reset_in),
                    .age_change_enable_in (age_en[IDX]),
                    .takeover_enable_in   (take_en[IDX]),
                    .player_reg_in        (player_reg),
                    .first_turn_reg_in    (first_turn),
                    .state_out            (cs[IDX])
                );

                // Pack into the flat bus for display/debug.
                assign all_cell_states_out[3*IDX +: 3] = cs[IDX];

            end
        end
    endgenerate

    // Selected-cell state (used to generate the error flags).
    wire [4:0] sel_idx;
    assign sel_idx = rowNum * 3'd5 + {2'b00, colNum};

    reg [2:0] selected_cell_state;
    integer k;
    always @(*) begin
        selected_cell_state = EMPTY;
        for (k = 0; k < 25; k = k + 1) begin
            if (sel_idx == k[4:0])
                selected_cell_state = cs[k];
        end
    end

    // Errors based on what’s currently in the selected cell.
    wire selected_is_empty = (selected_cell_state == EMPTY);
    wire selected_is_other = !selected_is_empty
                             && (selected_cell_state != EXP)
                             && (selected_cell_state[0] != player_reg);

    assign cell_is_empty_error_out         = selected_is_empty && !first_turn;
    assign cell_is_other_player_error_out  = selected_is_other;

    // Global board status bits.

    // Any cell currently in EXP?
    wire [24:0] is_exp;
    genvar gi;
    generate
        for (gi = 0; gi < 25; gi = gi + 1) begin : exp_detect
            assign is_exp[gi] = (cs[gi] == EXP);
        end
    endgenerate
    assign any_exploding_out = |is_exp;

    // Win detection: once the first round is over, if only one player has
    // any owned cells remaining, that player wins.
    wire [24:0] is_p1;
    wire [24:0] is_p2;
    generate
        for (gi = 0; gi < 25; gi = gi + 1) begin : win_detect
            assign is_p1[gi] = (cs[gi] != EMPTY) && (cs[gi] != EXP)
                               && (cs[gi][0] == 1'b0);
            assign is_p2[gi] = (cs[gi] != EMPTY) && (cs[gi] != EXP)
                               && (cs[gi][0] == 1'b1);
        end
    endgenerate

    wire any_p1 = |is_p1;
    wire any_p2 = |is_p2;

    // Only declare a winner after both players have had a first move.
    assign have_a_winner_out = !first_turn
                               && ((any_p1 && !any_p2) || (!any_p1 && any_p2));

    // Winner ID (only meaningful when have_a_winner_out is high).
    assign winner_player_out = any_p2 ? 1'b1 : 1'b0;

endmodule
