`timescale 1ns / 1ps

// Color Wars game datapath
//
// Contains:
//   - 25 cell_fsm instances (5x5 grid) with parallel explosion wiring
//   - One-hot row/column decoding
//   - Input validation (errors reported to FSM)
//   - Player register and first-turn tracking
//   - Win detection
//
// Explosion propagation is fully combinational: each cell's takeover_enable
// is the OR of its orthogonal neighbors being in the EXP state. One "layer"
// of explosions resolves per clka/clkb cycle; chain reactions naturally
// propagate across multiple cycles while the FSM holds in ITERATE.
//
// Cell indexing: cell index = row * 5 + col  (0-24, row-major order)
//   Neighbor offsets: up = idx-5, down = idx+5, left = idx-1, right = idx+1

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

    // ---------------------------------------------------------------
    // State encoding (must match cell_fsm parameters)
    // ---------------------------------------------------------------
    localparam EMPTY = 3'b000;
    localparam EXP   = 3'b001;

    // ---------------------------------------------------------------
    // Player register & first-turn tracking
    // ---------------------------------------------------------------
    reg player_reg;
    reg [1:0] move_count;

    always @(negedge clka_in) begin
        if (reset_in)
            player_reg <= 1'b0;         // Player 1 goes first
        else if (change_player_in)
            player_reg <= ~player_reg;
    end

    always @(negedge clka_in) begin
        if (reset_in)
            move_count <= 2'd0;
        else if (change_player_in && move_count < 2'd2)
            move_count <= move_count + 2'd1;
    end

    wire first_turn = (move_count < 2'd2);

    assign player_reg_out  = player_reg;
    assign first_turn_out  = first_turn;

    // ---------------------------------------------------------------
    // One-hot row/column decoding
    // ---------------------------------------------------------------
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

    // ---------------------------------------------------------------
    // Input validation errors (combinational)
    // ---------------------------------------------------------------
    // Multiple buttons pressed in the same row or column group
    wire multi_row = (row_in & (row_in - 5'd1)) != 5'd0;
    wire multi_col = (column_in & (column_in - 5'd1)) != 5'd0;
    assign multiple_inputs_error_out = multi_row || multi_col;

    // No button pressed for row or column
    assign empty_row_or_col_error_out = (row_in == 5'd0) || (column_in == 5'd0);

    // ---------------------------------------------------------------
    // 25 cell instances + wiring
    // ---------------------------------------------------------------
    wire [2:0] cs       [0:24];   // cell state outputs
    wire       age_en   [0:24];   // age_change_enable per cell
    wire       take_en  [0:24];   // takeover_enable per cell

    genvar r, c;
    generate
        for (r = 0; r < 5; r = r + 1) begin : row_gen
            for (c = 0; c < 5; c = c + 1) begin : col_gen

                localparam integer IDX = r * 5 + c;

                // --- Explosion propagation wiring ---
                // Each cell's takeover_enable = OR of neighbors in EXP state.
                // Boundary cells get 0 for missing neighbors.
                // Uses generate-if so out-of-range indices are never elaborated.
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

                // --- Age-change enable ---
                // Only the selected cell gets this, only when FSM says start.
                assign age_en[IDX] = (r[2:0] == rowNum) && (c[2:0] == colNum)
                                     && start_iteration_in;

                // --- Cell instance ---
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

                // --- Collect into flat output bus ---
                assign all_cell_states_out[3*IDX +: 3] = cs[IDX];

            end
        end
    endgenerate

    // ---------------------------------------------------------------
    // Selected-cell state mux (for input validation)
    // ---------------------------------------------------------------
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

    // Cell-content errors
    wire selected_is_empty = (selected_cell_state == EMPTY);
    wire selected_is_other = !selected_is_empty
                             && (selected_cell_state != EXP)
                             && (selected_cell_state[0] != player_reg);

    assign cell_is_empty_error_out         = selected_is_empty && !first_turn;
    assign cell_is_other_player_error_out  = selected_is_other;

    // ---------------------------------------------------------------
    // Global board status
    // ---------------------------------------------------------------

    // Any cell currently exploding?
    wire [24:0] is_exp;
    genvar gi;
    generate
        for (gi = 0; gi < 25; gi = gi + 1) begin : exp_detect
            assign is_exp[gi] = (cs[gi] == EXP);
        end
    endgenerate
    assign any_exploding_out = |is_exp;

    // Win detection: all non-empty, non-EXP cells belong to one player
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

    // Winner exists when only one player has cells on the board,
    // and we're past the first round (both players have placed).
    assign have_a_winner_out = !first_turn
                               && ((any_p1 && !any_p2) || (!any_p1 && any_p2));

    // Which player won (only meaningful when have_a_winner_out == 1)
    assign winner_player_out = any_p2 && have_a_winner_out;

endmodule
