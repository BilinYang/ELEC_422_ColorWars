`timescale 1ns / 1ps

// ============================================================================
// Integration testbench for Color Wars
//
// Tests the full game flow including:
//   A) Reset & input validation (partial inputs do nothing)
//   B) First game: P1 places, P2 places, P1 explodes -> chain -> P1 wins
//   C) Reset & multi-input error detection
//   D) Confirm edge detection (holding button, release+re-press)
//   E) Explode both initial cells after edge-detection game
//   F) Full game ending in P2 victory via chain reaction
//   G) Final reset
//
// Cell state encoding:
//   000 = EMPTY    010 = P1_1    100 = P1_2    110 = P1_3
//   001 = EXP      011 = P2_1    101 = P2_2    111 = P2_3
//
// Grid coordinate convention:
//   row 0 = 5'b00001, row 1 = 5'b00010, row 2 = 5'b00100,
//   row 3 = 5'b01000, row 4 = 5'b10000  (same for columns)
// ============================================================================

module tb_colorwars;

    // ------------------------------------------------------------------
    // State-encoding parameters (for readable checks)
    // ------------------------------------------------------------------
    localparam EMPTY = 3'b000;
    localparam P1_1  = 3'b010;
    localparam P1_2  = 3'b100;
    localparam P1_3  = 3'b110;
    localparam P2_1  = 3'b011;
    localparam P2_2  = 3'b101;
    localparam P2_3  = 3'b111;
    localparam EXP   = 3'b001;

    // FSM states
    localparam FSM_IDLE     = 3'd0;
    localparam FSM_GAME_END = 3'd3;

    // ------------------------------------------------------------------
    // DUT signals
    // ------------------------------------------------------------------
    reg         clka, clkb;
    reg         reset;
    reg  [4:0]  row, column;
    reg         confirm;

    wire        show_empty_error;
    wire        show_owner_error;
    wire        show_row_col_error;
    wire        show_multi_error;
    wire [2:0]  state;
    wire        player_reg;
    wire        first_turn;
    wire        game_over;
    wire        winner_player;
    wire [74:0] all_cell_states;

    // ------------------------------------------------------------------
    // DUT instantiation
    // ------------------------------------------------------------------
    colorwars_top uut (
        .clka             (clka),
        .clkb             (clkb),
        .reset            (reset),
        .row              (row),
        .column           (column),
        .confirm          (confirm),
        .show_empty_error (show_empty_error),
        .show_owner_error (show_owner_error),
        .show_row_col_error (show_row_col_error),
        .show_multi_error (show_multi_error),
        .state            (state),
        .player_reg       (player_reg),
        .first_turn       (first_turn),
        .game_over        (game_over),
        .winner_player    (winner_player),
        .all_cell_states  (all_cell_states)
    );

    // ------------------------------------------------------------------
    // Non-overlapping two-phase clock generation
    //   Period = 20 ns total.
    //   clka pulse: t=0..5 high, 5..10 low
    //   clkb pulse: t=10..15 high, 15..20 low
    //   negedge clka at t = 5, 25, 45 ...
    //   negedge clkb at t = 15, 35, 55 ...
    // ------------------------------------------------------------------
    initial begin clka = 0; clkb = 0; end
    always begin
        #5  clka = 1;
        #5  clka = 0;
        #5  clkb = 1;
        #5  clkb = 0;
    end

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------
    reg [2:0] cell_val;

    task get_cell;
        input integer r;
        input integer c;
        integer idx;
        begin
            idx = r * 5 + c;
            cell_val = all_cell_states[3*idx +: 3];
        end
    endtask

    // One full two-phase clock cycle
    task cycle;
        begin
            @(negedge clka);
            @(negedge clkb);
        end
    endtask

    task clear_inputs;
        begin
            row     = 5'd0;
            column  = 5'd0;
            confirm = 1'b0;
        end
    endtask

    // Apply a move and wait for FSM to return to IDLE or GAME_END
    task make_move;
        input integer r;
        input integer c;
        integer watchdog;
        begin
            row     = (5'd1 << r);
            column  = (5'd1 << c);
            confirm = 1'b1;

            cycle;  // rising edge detected, IDLE -> INPUT_VERIFICATION
            cycle;  // INPUT_VERIFICATION -> ITERATE (or IDLE on error)

            clear_inputs;

            watchdog = 0;
            while (state != FSM_IDLE && state != FSM_GAME_END && watchdog < 100) begin
                cycle;
                watchdog = watchdog + 1;
            end

            if (watchdog >= 100)
                $display("  ERROR: Watchdog timeout! FSM stuck in state %0d", state);
        end
    endtask

    task print_board;
        integer r, c, idx;
        reg [2:0] s;
        begin
            $display("  Board (3-bit state per cell, row-major):");
            $display("        c0   c1   c2   c3   c4");
            for (r = 0; r < 5; r = r + 1) begin
                $write("  r%0d: ", r);
                for (c = 0; c < 5; c = c + 1) begin
                    idx = r * 5 + c;
                    s = all_cell_states[3*idx +: 3];
                    $write(" %b ", s);
                end
                $write("\n");
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Pass/fail tracking
    // ------------------------------------------------------------------
    integer test_num;
    integer pass_count;
    integer fail_count;

    task check_cell;
        input integer r;
        input integer c;
        input [2:0] expected;
        integer idx;
        reg [2:0] actual;
        begin
            idx = r * 5 + c;
            actual = all_cell_states[3*idx +: 3];
            if (actual === expected) begin
                pass_count = pass_count + 1;
            end
            else begin
                $display("  FAIL test %0d: cell(%0d,%0d) = %b, expected %b",
                         test_num, r, c, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_signal;
        input [63:0] name;  // signal name for display
        input integer val;
        input integer expected;
        begin
            if (val === expected)
                pass_count = pass_count + 1;
            else begin
                $display("  FAIL test %0d: got %0d, expected %0d", test_num, val, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Check that the entire board is empty
    task check_all_empty;
        begin : blk_all_empty
            integer ri, ci;
            for (ri = 0; ri < 5; ri = ri + 1)
                for (ci = 0; ci < 5; ci = ci + 1)
                    check_cell(ri, ci, EMPTY);
        end
    endtask

    // ------------------------------------------------------------------
    // Main test sequence
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("tb_colorwars.vcd");
        $dumpvars(0, tb_colorwars);

        test_num   = 0;
        pass_count = 0;
        fail_count = 0;

        reset   = 1'b0;
        row     = 5'd0;
        column  = 5'd0;
        confirm = 1'b0;

        // =============================================================
        // PART A: RESET & INPUT VALIDATION
        // =============================================================

        // ------ TEST 1: Reset ------
        test_num = 1;
        $display("\n========================================");
        $display("=== TEST %0d: Power-on reset ===", test_num);
        $display("========================================");
        reset = 1'b1;
        cycle; cycle;          // hold reset for 2 full cycles
        reset = 1'b0;
        cycle;                 // let FSM settle into IDLE

        $display("  state=%0d  player=%0d  first_turn=%b  game_over=%b",
                 state, player_reg, first_turn, game_over);
        check_signal("state",      state,      FSM_IDLE);
        check_signal("player",     player_reg, 0);
        check_signal("first_turn", first_turn,  1);
        check_signal("game_over",  game_over,   0);
        check_all_empty;
        $display("  PASS: All 25 cells EMPTY, FSM in IDLE, P1's turn, first_turn active");

        // ------ TEST 2: Row-only input (no column, no confirm) -> nothing ------
        test_num = 2;
        $display("\n=== TEST %0d: Row input only (01000), no col, no confirm ===", test_num);
        row = 5'b01000;
        cycle; cycle;
        // FSM should still be IDLE
        check_signal("state", state, FSM_IDLE);
        check_all_empty;
        row = 5'd0;  // clear row
        $display("  PASS: No state change from row-only input");

        // ------ TEST 3: Column-only input -> nothing ------
        test_num = 3;
        $display("\n=== TEST %0d: Column input only (01000), no row, no confirm ===", test_num);
        column = 5'b01000;
        cycle; cycle;
        check_signal("state", state, FSM_IDLE);
        check_all_empty;
        column = 5'd0;  // clear column
        $display("  PASS: No state change from column-only input");

        // ------ TEST 4: Both row & column, no confirm -> nothing ------
        test_num = 4;
        $display("\n=== TEST %0d: Row+Col (01000,01000), no confirm ===", test_num);
        row    = 5'b01000;
        column = 5'b01000;
        cycle; cycle;
        check_signal("state", state, FSM_IDLE);
        check_all_empty;
        // NOTE: Do NOT clear row/column — we'll add confirm next
        $display("  PASS: No state change without confirm");

        // ------ TEST 5: Add confirm (row/col still 01000) -> P1 first move at (3,3) ------
        test_num = 5;
        $display("\n=== TEST %0d: Confirm with row/col held -> P1 places at (3,3) ===", test_num);
        confirm = 1'b1;
        cycle;                 // confirm rising edge detected, IDLE -> INPUT_VERIFICATION
        confirm = 1'b0;
        cycle;                 // INPUT_VERIFICATION -> ITERATE
        clear_inputs;

        // Wait for FSM to return to IDLE (no explosion — just a placement)
        repeat (10) cycle;

        $display("  state=%0d  player=%0d  first_turn=%b", state, player_reg, first_turn);
        check_signal("state", state, FSM_IDLE);
        check_signal("player", player_reg, 1);  // switched to P2
        check_signal("first_turn", first_turn, 1);  // still first round (1 of 2 moves done)
        check_cell(3, 3, P1_3);  // first placement = age 3
        $display("  PASS: P1 placed at (3,3) with age 3 (P1_3=110)");

        // =============================================================
        // PART B: FIRST GAME — P1 WINS
        // =============================================================

        // ------ TEST 6: P2 first move at (3,2) ------
        test_num = 6;
        $display("\n=== TEST %0d: P2 places at (3,2) ===", test_num);
        $display("  player=%0d  first_turn=%b", player_reg, first_turn);
        row = 5'b01000; column = 5'b00100; confirm = 1'b1;
        cycle;          // IDLE -> INPUT_VERIFICATION (rising edge)
        cycle;          // INPUT_VERIFICATION -> ITERATE (needs row/col valid!)
        clear_inputs;
        repeat (5) cycle;

        check_signal("state", state, FSM_IDLE);
        check_signal("player", player_reg, 0);  // back to P1
        check_signal("first_turn", first_turn, 0);  // first round complete (2 moves done)
        check_cell(3, 2, P2_3);
        $display("  PASS: P2 placed at (3,2) with age 3. First turn now OFF.");

        // ------ TEST 7: Error — P1 clicks empty cell (3,1) after first round ------
        test_num = 7;
        $display("\n=== TEST %0d: P1 clicks empty cell (3,1) -> empty error ===", test_num);
        row = 5'b01000; column = 5'b00010; confirm = 1'b1;
        cycle;          // rising edge -> IDLE -> INPUT_VERIFICATION
        cycle;          // INPUT_VERIFICATION sees empty cell -> error -> IDLE
        clear_inputs;
        cycle;

        $display("  show_empty_error was pulsed (check waveform)");
        // After error, FSM returns to IDLE, board unchanged
        check_signal("state", state, FSM_IDLE);
        check_signal("player", player_reg, 0);  // still P1's turn (no move applied)
        check_cell(3, 1, EMPTY);  // cell unchanged
        $display("  PASS: Empty-cell error caught, turn not consumed");

        // ------ TEST 8: P1 clicks (3,3) -> EXPLOSION -> chain -> P1 WINS ------
        // (3,3) is P1_3. Clicking it: P1_3 -> EXP.
        // Explosion at (3,3): neighbors (2,3), (4,3), (3,2), (3,4) get takeover.
        //   (3,2) is P2_3 -> EXP (CHAIN REACTION!)
        //   Others are EMPTY -> P1_1
        // Then (3,2) explodes: neighbors (2,2), (4,2), (3,1), (3,3) -> P1_1
        //   (3,3) was EMPTY after its own explosion -> P1_1
        // Result: All cells are P1 or EMPTY. P1 wins!
        test_num = 8;
        $display("\n=== TEST %0d: P1 clicks (3,3) -> EXPLOSION + CHAIN -> P1 WINS ===", test_num);
        $display("  Before explosion:");
        print_board;

        make_move(3, 3);

        $display("  After chain reaction:");
        print_board;

        // Verify the final board state
        check_cell(3, 3, P1_1);  // got dot from (3,2)'s explosion
        check_cell(2, 3, P1_1);  // from (3,3) explosion
        check_cell(4, 3, P1_1);  // from (3,3) explosion
        check_cell(3, 4, P1_1);  // from (3,3) explosion
        check_cell(3, 2, EMPTY); // exploded -> empty
        check_cell(2, 2, P1_1);  // from (3,2) explosion
        check_cell(4, 2, P1_1);  // from (3,2) explosion
        check_cell(3, 1, P1_1);  // from (3,2) explosion

        // ------ TEST 9: Verify game-over state ------
        test_num = 9;
        $display("\n=== TEST %0d: Game-over check ===", test_num);
        check_signal("game_over", game_over, 1);
        check_signal("winner",    winner_player, 0);  // P1 won
        check_signal("state",     state, FSM_GAME_END);
        $display("  PASS: game_over=1, winner=P1, FSM in GAME_END");

        // =============================================================
        // PART C: RESET & MULTI-INPUT ERROR TESTING
        // =============================================================

        // ------ TEST 10: Reset mid-game ------
        test_num = 10;
        $display("\n========================================");
        $display("=== TEST %0d: Reset after game ===", test_num);
        $display("========================================");
        repeat (3) cycle;      // wait a bit
        reset = 1'b1;
        cycle; cycle; cycle;   // reset for 3 cycles
        reset = 1'b0;
        cycle;

        check_signal("state",      state,      FSM_IDLE);
        check_signal("player",     player_reg, 0);
        check_signal("first_turn", first_turn,  1);
        check_signal("game_over",  game_over,   0);
        check_all_empty;
        $display("  PASS: Full reset verified — clean slate");

        // ------ TEST 11: Multiple row inputs error ------
        test_num = 11;
        $display("\n=== TEST %0d: Multi-input error (row=01010) ===", test_num);
        row = 5'b01010; column = 5'b00100; confirm = 1'b1;
        cycle;          // rising edge -> IDLE -> INPUT_VERIFICATION
        cycle;          // INPUT_VERIFICATION -> error -> IDLE
        clear_inputs;
        cycle;

        check_signal("state", state, FSM_IDLE);
        check_all_empty;  // no move applied
        $display("  PASS: Multiple-input error caught (row had 2 bits set)");

        // ------ TEST 12: Multiple column inputs error ------
        test_num = 12;
        $display("\n=== TEST %0d: Multi-input error (col=00110) ===", test_num);
        row = 5'b00100; column = 5'b00110; confirm = 1'b1;
        cycle;          // rising edge -> IDLE -> INPUT_VERIFICATION
        cycle;          // INPUT_VERIFICATION -> error -> IDLE
        clear_inputs;
        cycle;

        check_signal("state", state, FSM_IDLE);
        check_all_empty;
        $display("  PASS: Multiple-input error caught (col had 2 bits set)");

        // ------ TEST 13: Empty column error (row valid, col=00000) ------
        // The IDLE guard (row!=0 && col!=0) prevents the FSM from even
        // reaching INPUT_VERIFICATION — it silently stays in IDLE.
        test_num = 13;
        $display("\n=== TEST %0d: Row valid (01000), column empty (00000) ===", test_num);
        row = 5'b01000; column = 5'b00000; confirm = 1'b1;
        cycle;          // confirm rising edge, but col=0 -> IDLE guard blocks
        cycle;
        clear_inputs;
        cycle;

        check_signal("state", state, FSM_IDLE);
        check_all_empty;
        $display("  PASS: FSM stayed in IDLE — column was empty");

        // ------ TEST 14: Empty row error (row=00000, col valid) ------
        test_num = 14;
        $display("\n=== TEST %0d: Row empty (00000), column valid (01000) ===", test_num);
        row = 5'b00000; column = 5'b01000; confirm = 1'b1;
        cycle;          // confirm rising edge, but row=0 -> IDLE guard blocks
        cycle;
        clear_inputs;
        cycle;

        check_signal("state", state, FSM_IDLE);
        check_all_empty;
        $display("  PASS: FSM stayed in IDLE — row was empty");

        // =============================================================
        // PART D: CONFIRM EDGE DETECTION
        // =============================================================

        // ------ TEST 15: Hold confirm for 10 cycles -> only 1 move ------
        test_num = 15;
        $display("\n========================================");
        $display("=== TEST %0d: Confirm held 10 cycles -> 1 move only ===", test_num);
        $display("========================================");
        row = 5'b01000; column = 5'b00100; confirm = 1'b1;
        // Hold all three signals for 10 full cycles
        repeat (10) cycle;

        // Check: only one move was applied (P1 first placement at (3,2))
        check_cell(3, 2, P1_3);
        check_signal("player", player_reg, 1);  // switched to P2 once
        check_signal("first_turn", first_turn, 1);  // only 1 of 2 first moves done
        $display("  PASS: P1 placed at (3,2)=P1_3, only ONE move despite 10 held cycles");

        // ------ TEST 16: Change inputs without releasing confirm -> no new move ------
        test_num = 16;
        $display("\n=== TEST %0d: Change row/col while confirm held -> no move ===", test_num);
        // Release row and column but keep confirm HIGH
        row = 5'b00100; column = 5'b00010;
        // confirm still 1'b1 — no rising edge!
        repeat (5) cycle;

        // Cell (2,1) should still be EMPTY — no move was applied
        check_cell(2, 1, EMPTY);
        check_signal("player", player_reg, 1);  // still P2's turn
        $display("  PASS: No move applied — confirm never had a rising edge");

        // ------ TEST 17: Release confirm 1 cycle, re-press -> P2 places at (2,1) ------
        test_num = 17;
        $display("\n=== TEST %0d: Release + re-press confirm -> P2 places at (2,1) ===", test_num);
        // Release confirm for 1 cycle (row/col stay at 00100/00010)
        confirm = 1'b0;
        cycle;
        // Re-press confirm — this creates a rising edge!
        confirm = 1'b1;
        cycle;      // rising edge -> IDLE -> INPUT_VERIFICATION
        cycle;      // INPUT_VERIFICATION -> ITERATE (row/col still valid)
        clear_inputs;
        repeat (5) cycle;

        check_cell(2, 1, P2_3);
        check_signal("player", player_reg, 0);  // back to P1
        check_signal("first_turn", first_turn, 0);  // both first moves done
        $display("  PASS: P2 placed at (2,1)=P2_3 after confirm re-press. First turn OFF.");

        // =============================================================
        // PART E: EXPLODE BOTH INITIAL CELLS
        // =============================================================

        // ------ TEST 18: P1 explodes (3,2) ------
        // (3,2) is P1_3. Click -> EXP -> neighbors get P1_1:
        //   (2,2)=P1_1, (4,2)=P1_1, (3,1)=P1_1, (3,3)=P1_1
        test_num = 18;
        $display("\n=== TEST %0d: P1 explodes (3,2) ===", test_num);
        make_move(3, 2);

        $display("  After P1 explosion:");
        print_board;
        check_cell(3, 2, EMPTY);
        check_cell(2, 2, P1_1);
        check_cell(4, 2, P1_1);
        check_cell(3, 1, P1_1);
        check_cell(3, 3, P1_1);
        $display("  PASS: (3,2) exploded, 4 neighbors -> P1_1");

        // ------ TEST 19: P2 explodes (2,1) ------
        // (2,1) is P2_3. Click -> EXP -> neighbors:
        //   (1,1)=EMPTY -> P2_1
        //   (3,1)=P1_1  -> P2_2 (takeover! age goes from 1 to 2 as P2)
        //   (2,0)=EMPTY -> P2_1
        //   (2,2)=P1_1  -> P2_2 (takeover!)
        test_num = 19;
        $display("\n=== TEST %0d: P2 explodes (2,1) ===", test_num);
        make_move(2, 1);

        $display("  After P2 explosion:");
        print_board;
        check_cell(2, 1, EMPTY);
        check_cell(1, 1, P2_1);
        check_cell(3, 1, P2_2);  // was P1_1, taken over
        check_cell(2, 0, P2_1);
        check_cell(2, 2, P2_2);  // was P1_1, taken over
        // P1 cells remaining:
        check_cell(4, 2, P1_1);
        check_cell(3, 3, P1_1);
        $display("  PASS: (2,1) exploded, 2 cells taken over from P1");

        $display("\n  --- Board summary after both explosions ---");
        $display("  P1 cells: (4,2)=P1_1, (3,3)=P1_1");
        $display("  P2 cells: (1,1)=P2_1, (3,1)=P2_2, (2,0)=P2_1, (2,2)=P2_2");
        print_board;

        // =============================================================
        // PART F: FULL GAME ENDING IN P2 VICTORY
        //
        // The board after Part E doesn't allow a quick P2 chain-reaction
        // win (P1 and P2 cells aren't adjacent). We reset and play a
        // fresh game designed so P2 wins via chain reaction.
        //
        // Setup: P1 at (2,1), P2 at (2,3) — same row, separated by 1.
        // After both explode, P2 takes over (2,2) and has a head start.
        // Then P2 builds up cells and chain-reacts through all P1 cells.
        // =============================================================

        // ------ TEST 20: Reset for P2-wins game ------
        test_num = 20;
        $display("\n========================================");
        $display("=== TEST %0d: Reset for P2-wins game ===", test_num);
        $display("========================================");
        reset = 1'b1;
        cycle; cycle;
        reset = 1'b0;
        cycle;

        check_signal("state",  state,  FSM_IDLE);
        check_signal("player", player_reg, 0);
        check_signal("first_turn", first_turn, 1);
        check_all_empty;
        $display("  PASS: Clean reset");

        // ------ TEST 21: P1 places at (2,1), P2 places at (2,3) ------
        test_num = 21;
        $display("\n=== TEST %0d: First-round placements ===", test_num);
        make_move(2, 1);  // P1 at (2,1) -> P1_3
        check_cell(2, 1, P1_3);
        make_move(2, 3);  // P2 at (2,3) -> P2_3
        check_cell(2, 3, P2_3);
        check_signal("first_turn", first_turn, 0);
        $display("  PASS: P1 at (2,1)=P1_3, P2 at (2,3)=P2_3");

        // ------ TEST 22: Owner error — P1 clicks P2's cell ------
        // It's P1's turn (player_reg=0). P2's cell is at (2,3)=P2_3.
        // Clicking it should trigger show_owner_error and return to IDLE
        // without consuming the turn.
        test_num = 22;
        $display("\n=== TEST %0d: Owner error — P1 clicks P2 cell (2,3) ===", test_num);
        row = 5'b00100; column = 5'b01000; confirm = 1'b1;
        cycle;          // rising edge -> IDLE -> INPUT_VERIFICATION
        cycle;          // INPUT_VERIFICATION -> owner error -> IDLE
        clear_inputs;
        cycle;

        check_signal("state", state, FSM_IDLE);
        check_signal("player", player_reg, 0);  // still P1's turn (no move applied)
        check_cell(2, 3, P2_3);  // cell unchanged
        check_cell(2, 1, P1_3);  // P1 cell unchanged
        $display("  PASS: Owner error caught — P1 cannot click P2's cell");

        // ------ TEST 23: P1 explodes (2,1) ------
        // Neighbors: (1,1), (3,1), (2,0), (2,2) -> P1_1
        test_num = 23;
        $display("\n=== TEST %0d: P1 explodes (2,1) ===", test_num);
        make_move(2, 1);
        check_cell(2, 1, EMPTY);
        check_cell(1, 1, P1_1);
        check_cell(3, 1, P1_1);
        check_cell(2, 0, P1_1);
        check_cell(2, 2, P1_1);
        $display("  PASS: 4 neighbors -> P1_1");

        // ------ TEST 24: P2 explodes (2,3) ------
        // Neighbors: (1,3), (3,3), (2,2), (2,4)
        //   (2,2) was P1_1 -> P2_2 (takeover!)
        //   Rest EMPTY -> P2_1
        test_num = 24;
        $display("\n=== TEST %0d: P2 explodes (2,3) — takes over (2,2)! ===", test_num);
        make_move(2, 3);
        $display("  After both explosions:");
        print_board;
        check_cell(2, 3, EMPTY);
        check_cell(1, 3, P2_1);
        check_cell(3, 3, P2_1);
        check_cell(2, 2, P2_2);  // takeover from P1
        check_cell(2, 4, P2_1);
        // P1 remaining:
        check_cell(1, 1, P1_1);
        check_cell(3, 1, P1_1);
        check_cell(2, 0, P1_1);
        $display("  PASS: P2 took over (2,2). P1 has 3 cells, P2 has 4 cells.");

        // ------ TEST 25: Age cycling — build toward P2 explosion ------
        // Strategy: P2 will age (2,2) from P2_2 -> P2_3 -> EXP, spreading
        // P2 cells. Then age (2,1) and chain-react through P1's age-3 cells.
        //
        // Move sequence:
        //   P1 clicks (1,1): P1_1->P1_2    P2 clicks (2,2): P2_2->P2_3
        //   P1 clicks (3,1): P1_1->P1_2    P2 clicks (2,2): P2_3->EXP!
        //     (2,2) explodes -> (1,2), (3,2), (2,1), (2,3) all -> P2_1
        //   P1 clicks (1,1): P1_2->P1_3    P2 clicks (2,1): P2_1->P2_2
        //   P1 clicks (3,1): P1_2->P1_3    P2 clicks (2,1): P2_2->P2_3
        //   P1 clicks (2,0): P1_1->P1_2    P2 clicks (2,1): P2_3->EXP!
        //     -> CHAIN REACTION: takes (1,1) P1_3->EXP, (3,1) P1_3->EXP
        //     -> Both P1 cells explode, all results go to P2
        //     -> (2,0) P1_2 taken over -> P2_3
        //     -> NO P1 CELLS LEFT -> P2 WINS!
        test_num = 25;
        $display("\n=== TEST %0d: Age cycling toward P2 chain reaction ===", test_num);

        // Round 1: age up
        $display("  P1 clicks (1,1): P1_1->P1_2");
        make_move(1, 1);
        check_cell(1, 1, P1_2);

        $display("  P2 clicks (2,2): P2_2->P2_3");
        make_move(2, 2);
        check_cell(2, 2, P2_3);

        // Round 2: P1 ages, P2 explodes (2,2)!
        $display("  P1 clicks (3,1): P1_1->P1_2");
        make_move(3, 1);
        check_cell(3, 1, P1_2);

        $display("  P2 clicks (2,2): P2_3->EXP -> explosion!");
        make_move(2, 2);
        $display("  After (2,2) explosion:");
        print_board;
        check_cell(2, 2, EMPTY);
        check_cell(1, 2, P2_1);
        check_cell(3, 2, P2_1);
        check_cell(2, 1, P2_1);
        check_cell(2, 3, P2_1);

        // Round 3: continue building
        $display("  P1 clicks (1,1): P1_2->P1_3");
        make_move(1, 1);
        check_cell(1, 1, P1_3);

        $display("  P2 clicks (2,1): P2_1->P2_2");
        make_move(2, 1);
        check_cell(2, 1, P2_2);

        // Round 4: continue building
        $display("  P1 clicks (3,1): P1_2->P1_3");
        make_move(3, 1);
        check_cell(3, 1, P1_3);

        $display("  P2 clicks (2,1): P2_2->P2_3");
        make_move(2, 1);
        check_cell(2, 1, P2_3);

        // Round 5: P1's last move, then P2 triggers chain reaction!
        $display("  P1 clicks (2,0): P1_1->P1_2");
        make_move(2, 0);
        check_cell(2, 0, P1_2);

        $display("\n  >>> P2 clicks (2,1): P2_3->EXP -> CHAIN REACTION! <<<");
        $display("  Before the big explosion:");
        print_board;
        make_move(2, 1);

        // ------ TEST 26: Verify P2 chain reaction result ------
        // (2,1) explodes -> hits (1,1)=P1_3 -> EXP!, (3,1)=P1_3 -> EXP!,
        //                       (2,0)=P1_2 -> P2_3, (2,2)=EMPTY -> P2_1
        // (1,1) explodes -> (0,1), (2,1), (1,0), (1,2) -> P2
        // (3,1) explodes -> (2,1), (4,1), (3,0), (3,2) -> P2
        // All P1 cells eliminated!
        test_num = 26;
        $display("\n=== TEST %0d: P2 chain reaction — verify P2 wins ===", test_num);
        $display("  After chain reaction:");
        print_board;

        // No P1 cells should remain
        // (2,0) was taken over to P2_3
        check_cell(2, 0, P2_3);
        // (1,1) and (3,1) exploded -> EMPTY
        check_cell(1, 1, EMPTY);
        check_cell(3, 1, EMPTY);
        // Cells created by (1,1) explosion
        check_cell(0, 1, P2_1);
        check_cell(1, 0, P2_1);
        // Cells created by (3,1) explosion
        check_cell(4, 1, P2_1);
        check_cell(3, 0, P2_1);

        // ------ TEST 27: Game over — P2 wins ------
        test_num = 27;
        $display("\n=== TEST %0d: Game-over state — P2 should win ===", test_num);
        check_signal("game_over", game_over, 1);
        check_signal("winner",    winner_player, 1);  // P2!
        check_signal("state",     state, FSM_GAME_END);
        $display("  game_over=%b  winner_player=%b (1=P2)  state=%0d",
                 game_over, winner_player, state);
        $display("  PASS: P2 WINS via chain reaction!");

        // =============================================================
        // PART G: FINAL RESET
        // =============================================================

        // ------ TEST 28: Final reset — clean slate ------
        test_num = 28;
        $display("\n========================================");
        $display("=== TEST %0d: Final reset ===", test_num);
        $display("========================================");
        reset = 1'b1;
        cycle; cycle;
        reset = 1'b0;
        cycle;

        check_signal("state",      state,      FSM_IDLE);
        check_signal("player",     player_reg, 0);
        check_signal("first_turn", first_turn,  1);
        check_signal("game_over",  game_over,   0);
        check_all_empty;
        $display("  PASS: System fully reset and ready for new game");

        // =============================================================
        // RESULTS SUMMARY
        // =============================================================
        $display("\n============================================");
        $display("  RESULTS: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  SOME TESTS FAILED — check FAIL lines above");
        $display("============================================\n");

        #200;
        $finish;
    end

endmodule
