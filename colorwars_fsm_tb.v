`timescale 1ns / 1ps

// Integration-style testbench for Color Wars.
//
// This instantiates colorwars_top and pokes it through the same inputs the
// hardware would see: two-phase clocks, reset, one-hot row/col, and confirm.
//
// Handy decode when reading logs:
//   000 EMPTY, 001 EXP,
//   010/100/110 = P1 age 1/2/3,
//   011/101/111 = P2 age 1/2/3.

module tb_colorwars;

    // DUT I/O.
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

    // DUT instance.
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

    // Non-overlapping two-phase clock:
    // clka falls halfway between clkb falls, so the two phases never overlap.
    initial begin clka = 0; clkb = 0; end
    always begin
        #5  clka = 1;
        #5  clka = 0;
        #5  clkb = 1;
        #5  clkb = 0;
    end

    // Small helpers to keep the test readable.
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

    task make_move;
        input integer r;
        input integer c;
        integer watchdog;
        begin
            row     = (5'd1 << r);
            column  = (5'd1 << c);
            confirm = 1'b1;

            cycle;  // IDLE -> INPUT_VERIFICATION
            cycle;  // INPUT_VERIFICATION -> ITERATE (or IDLE on error)

            clear_inputs;

            watchdog = 0;
            while (state != 3'd0 && state != 3'd3 && watchdog < 50) begin
                cycle;
                watchdog = watchdog + 1;
            end

            if (watchdog >= 50)
                $display("ERROR: Watchdog timeout! FSM stuck in state %0d", state);
        end
    endtask

    task print_board;
        integer r, c, idx;
        reg [2:0] s;
        begin
            $display("  Board (each cell shown as 3-bit state):");
            for (r = 0; r < 5; r = r + 1) begin
                for (c = 0; c < 5; c = c + 1) begin
                    idx = r * 5 + c;
                    s = all_cell_states[3*idx +: 3];
                    $write("  %b", s);
                end
                $write("\n");
            end
        end
    endtask

    // Pass/fail counters.
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
                $display("  FAIL: cell(%0d,%0d) = %b, expected %b", r, c, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_val;
        input integer val;
        input integer expected;
        begin
            if (val === expected)
                pass_count = pass_count + 1;
            else begin
                $display("  FAIL: got %0d, expected %0d", val, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Main test sequence.
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

        // TEST 1: Reset should clear the board and set P1/first_turn.
        test_num = 1;
        $display("\n=== TEST %0d: Reset ===", test_num);
        reset = 1'b1;
        cycle; cycle;
        reset = 1'b0;
        cycle;

        $display("  state=%0d  player=%0d  first_turn=%b  game_over=%b",
                 state, player_reg, first_turn, game_over);
        check_val(state, 0);
        check_val(player_reg, 0);
        check_val(first_turn, 1);
        check_val(game_over, 0);
        begin : blk_reset1
            integer ri, ci;
            for (ri = 0; ri < 5; ri = ri + 1)
                for (ci = 0; ci < 5; ci = ci + 1)
                    check_cell(ri, ci, 3'b000);
        end
        $display("  All cells verified EMPTY");

        // TEST 2: P1 first move at (0,0) should claim it as P1_1.
        test_num = 2;
        $display("\n=== TEST %0d: P1 first move (0,0) ===", test_num);
        $display("  player=%0d  first_turn=%b", player_reg, first_turn);

        make_move(0, 0);

        get_cell(0, 0);
        $display("  Cell(0,0) = %b  (expect 010=P1_1)", cell_val);
        check_cell(0, 0, 3'b010);
        check_val(player_reg, 1);   // now P2's turn
        check_val(first_turn, 1);   // still first round
        print_board;

        // TEST 3: P2 first move at (4,4) should claim it as P2_1.
        test_num = 3;
        $display("\n=== TEST %0d: P2 first move (4,4) ===", test_num);

        make_move(4, 4);

        get_cell(4, 4);
        $display("  Cell(4,4) = %b  (expect 011=P2_1)", cell_val);
        check_cell(4, 4, 3'b011);
        check_val(player_reg, 0);   // back to P1
        check_val(first_turn, 0);   // first round complete

        // TEST 4: After first turn, clicking an empty cell should error.
        test_num = 4;
        $display("\n=== TEST %0d: Error — empty cell (2,2) ===", test_num);

        row = 5'b00100; column = 5'b00100; confirm = 1'b1;
        cycle;  // IDLE -> INPUT_VERIFICATION
        $display("  Errors: empty=%b owner=%b rowcol=%b multi=%b",
                 show_empty_error, show_owner_error,
                 show_row_col_error, show_multi_error);
        cycle;  // back to IDLE
        clear_inputs; cycle;

        check_cell(2, 2, 3'b000);
        check_val(state, 0);
        $display("  Rejected correctly — cell unchanged");

        // TEST 5: Clicking opponent-owned cell should error.
        test_num = 5;
        $display("\n=== TEST %0d: Error — opponent cell (4,4) ===", test_num);

        row = 5'b10000; column = 5'b10000; confirm = 1'b1;
        cycle;
        $display("  Errors: empty=%b owner=%b", show_empty_error, show_owner_error);
        cycle;
        clear_inputs; cycle;

        check_cell(4, 4, 3'b011);
        $display("  Rejected correctly — cell unchanged");

        // TEST 6: Multiple selections in a one-hot group should error.
        test_num = 6;
        $display("\n=== TEST %0d: Error — multiple rows ===", test_num);

        row = 5'b00011; column = 5'b00001; confirm = 1'b1;
        cycle;
        $display("  multi_err=%b (expect 1)", show_multi_error);
        cycle;
        clear_inputs; cycle;
        check_val(state, 0);

        // TEST 7: No column selected: FSM should stay in IDLE.
        test_num = 7;
        $display("\n=== TEST %0d: Guard — no column ===", test_num);

        row = 5'b00001; column = 5'd0; confirm = 1'b1;
        cycle;
        $display("  state=%0d (expect 0=IDLE)", state);
        check_val(state, 0);
        clear_inputs; cycle;

        // TEST 8: Aging a P1 cell should step P1_1 -> P1_2.
        test_num = 8;
        $display("\n=== TEST %0d: P1 ages (0,0) P1_1->P1_2 ===", test_num);
        make_move(0, 0);
        get_cell(0, 0);
        $display("  Cell(0,0) = %b  (expect 100=P1_2)", cell_val);
        check_cell(0, 0, 3'b100);

        // TEST 9: Aging a P2 cell should step P2_1 -> P2_2.
        test_num = 9;
        $display("\n=== TEST %0d: P2 ages (4,4) P2_1->P2_2 ===", test_num);
        make_move(4, 4);
        get_cell(4, 4);
        $display("  Cell(4,4) = %b  (expect 101=P2_2)", cell_val);
        check_cell(4, 4, 3'b101);

        // TEST 10: Aging should step P1_2 -> P1_3.
        test_num = 10;
        $display("\n=== TEST %0d: P1 ages (0,0) P1_2->P1_3 ===", test_num);
        make_move(0, 0);
        get_cell(0, 0);
        $display("  Cell(0,0) = %b  (expect 110=P1_3)", cell_val);
        check_cell(0, 0, 3'b110);

        // TEST 11: Aging should step P2_2 -> P2_3.
        test_num = 11;
        $display("\n=== TEST %0d: P2 ages (4,4) P2_2->P2_3 ===", test_num);
        make_move(4, 4);
        get_cell(4, 4);
        $display("  Cell(4,4) = %b  (expect 111=P2_3)", cell_val);
        check_cell(4, 4, 3'b111);

        // TEST 12: Corner explosion from (0,0): only two neighbors should get hit.
        test_num = 12;
        $display("\n=== TEST %0d: EXPLOSION at (0,0) ===", test_num);
        $display("  Before:");
        print_board;

        make_move(0, 0);

        $display("  After:");
        print_board;
        check_cell(0, 0, 3'b000);  // EMPTY
        check_cell(0, 1, 3'b010);  // P1_1 (takeover)
        check_cell(1, 0, 3'b010);  // P1_1 (takeover)
        check_cell(0, 2, 3'b000);  // unaffected
        check_cell(2, 0, 3'b000);  // unaffected
        $display("  Explosion OK: 2 neighbors received P1_1");

        // TEST 13: Player should still alternate after an explosion.
        test_num = 13;
        $display("\n=== TEST %0d: Player tracking ===", test_num);
        $display("  player_reg=%0d (expect 1=P2)", player_reg);
        check_val(player_reg, 1);

        // TEST 14: P2 corner explosion at (4,4).
        test_num = 14;
        $display("\n=== TEST %0d: P2 EXPLOSION at (4,4) ===", test_num);

        make_move(4, 4);

        $display("  After:");
        print_board;
        check_cell(4, 4, 3'b000);  // EMPTY
        check_cell(4, 3, 3'b011);  // P2_1
        check_cell(3, 4, 3'b011);  // P2_1
        $display("  Corner explosion OK");

        // TEST 15: Reset should work mid-game too.
        test_num = 15;
        $display("\n=== TEST %0d: Reset mid-game ===", test_num);

        reset = 1'b1;
        cycle; cycle;
        reset = 1'b0;
        cycle;

        check_val(state, 0);
        check_val(player_reg, 0);
        check_val(first_turn, 1);
        check_val(game_over, 0);
        begin : blk_reset2
            integer ri, ci;
            for (ri = 0; ri < 5; ri = ri + 1)
                for (ci = 0; ci < 5; ci = ci + 1)
                    check_cell(ri, ci, 3'b000);
        end
        $display("  Full reset verified");

        // TEST 16: Interior explosion at (2,2) should hit all 4 neighbors.
        test_num = 16;
        $display("\n=== TEST %0d: Interior explosion at (2,2) ===", test_num);

        // First-turn placements
        make_move(2, 2);  // P1 -> (2,2) = P1_1
        make_move(0, 0);  // P2 -> (0,0) = P2_1

        // Age up
        make_move(2, 2);  // P1: P1_1 -> P1_2
        make_move(0, 0);  // P2: P2_1 -> P2_2
        make_move(2, 2);  // P1: P1_2 -> P1_3
        make_move(0, 0);  // P2: P2_2 -> P2_3

        get_cell(2, 2);
        $display("  (2,2) = %b  (expect 110=P1_3)", cell_val);
        check_cell(2, 2, 3'b110);

        // Explode!
        $display("  Exploding center (2,2)...");
        make_move(2, 2);

        $display("  After interior explosion:");
        print_board;
        check_cell(2, 2, 3'b000);  // EMPTY (exploded)
        check_cell(1, 2, 3'b010);  // P1_1 (up)
        check_cell(3, 2, 3'b010);  // P1_1 (down)
        check_cell(2, 1, 3'b010);  // P1_1 (left)
        check_cell(2, 3, 3'b010);  // P1_1 (right)
        // Diagonals unaffected
        check_cell(1, 1, 3'b000);  // EMPTY
        check_cell(1, 3, 3'b000);  // EMPTY
        check_cell(3, 1, 3'b000);  // EMPTY
        check_cell(3, 3, 3'b000);  // EMPTY
        $display("  Interior explosion OK: 4 orthogonal neighbors, 0 diagonals");

        // TEST 17: Edge explosion from (1,2).
        test_num = 17;
        $display("\n=== TEST %0d: Edge cell explosion ===", test_num);

        // P2 explodes (0,0)
        make_move(0, 0);  // P2: P2_3 -> EXP -> EMPTY
        $display("  P2 exploded (0,0):");
        print_board;
        check_cell(0, 0, 3'b000);
        check_cell(0, 1, 3'b011);  // P2_1
        check_cell(1, 0, 3'b011);  // P2_1

        // P1 ages (1,2): P1_1 -> P1_2
        make_move(1, 2);
        // P2 ages (0,1): P2_1 -> P2_2
        make_move(0, 1);
        // P1 ages (1,2): P1_2 -> P1_3
        make_move(1, 2);
        get_cell(1, 2);
        $display("  (1,2) = %b  (expect 110=P1_3)", cell_val);
        check_cell(1, 2, 3'b110);

        // P2 ages (0,1)
        make_move(0, 1);

        // P1 explodes (1,2)!
        //   Neighbors: (0,2)=EMPTY, (2,2)=EMPTY, (1,1)=EMPTY, (1,3)=EMPTY
        //   All become P1_1
        $display("  Exploding (1,2)...");
        make_move(1, 2);

        $display("  After (1,2) explosion:");
        print_board;
        check_cell(1, 2, 3'b000);  // EMPTY
        check_cell(0, 2, 3'b010);  // P1_1 (up)
        check_cell(2, 2, 3'b010);  // P1_1 (down)
        check_cell(1, 1, 3'b010);  // P1_1 (left)
        check_cell(1, 3, 3'b010);  // P1_1 (right)
        $display("  Edge explosion OK");

        // Print a simple summary.
        $display("\n============================================");
        $display("  RESULTS: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  SOME TESTS FAILED");
        $display("============================================\n");

        #100;
        $finish;
    end

endmodule
