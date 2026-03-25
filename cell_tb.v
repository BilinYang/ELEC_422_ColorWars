// Quick sanity testbench for cell_fsm.
// Walks through the basic state progression for both players:
// claim -> age up -> explode -> clear.

module cell_tb ();

    reg clka, clkb;
    reg ace;    // age_change_enable
    reg te;     // takeover_enable
    reg preg;   // player_reg (0 = P1, 1 = P2)
    reg ftreg;  // first_turn_reg
    wire [2:0] state;

    cell_fsm main (
        .clka_in(clka),
        .clkb_in(clkb),
        .age_change_enable_in(ace),
        .takeover_enable_in(te),
        .player_reg_in(preg),
        .first_turn_reg_in(ftreg),
        .state_out(state)
    );

    // Two-phase clocking: clka computes, clkb latches.
    task clock_cycle;
    begin
        clka = 0; clkb = 0; #10;
        clka = 1; clkb = 0; #10;
        clka = 0; clkb = 0; #10;
        clka = 0; clkb = 1; #10;
    end
    endtask

    initial begin
        // Give the DUT a moment to settle.
        clock_cycle;

        // Start clean.
        te = 0; ace = 0; clock_cycle;

        // Player 1: claim an empty cell, age it up, then pop it.
        ftreg = 1; preg = 0; clock_cycle;  // set up for first turn
        ace = 1; te = 0; clock_cycle;      // claim cell -> P1_1
        ftreg = 0; clock_cycle;            // no longer first turn
        ace = 1; clock_cycle;              // age up -> P1_2
        ace = 0; clock_cycle;              // idle
        te = 1; clock_cycle;               // takeover (same player) -> P1_3
        ace = 1; te = 0; clock_cycle;      // age up -> EXP
        ace = 1; clock_cycle;              // should return to EMPTY
        
        // Back to idle inputs.
        te = 0; ace = 0; clock_cycle;

        // Player 2: same idea.
        ftreg = 1; preg = 1; clock_cycle;  // first turn, player 2
        ace = 1; te = 0; clock_cycle;      // claim cell -> P2_1
        ftreg = 0; clock_cycle;
        ace = 1; clock_cycle;              // -> P2_2
        ace = 0; clock_cycle;
        te = 1; clock_cycle;               // -> P2_3
        ace = 1; te = 0; clock_cycle;      // -> EXP
        ace = 1; clock_cycle;              // -> EMPTY

        // Done.
        te = 0; ace = 0; clock_cycle;
    end

endmodule
