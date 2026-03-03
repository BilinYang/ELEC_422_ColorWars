// Testbench for cell_fsm module
// Tests state transitions for both players through the full age cycle (1->2->3->explode)

module cell_tb ();

    reg clka, clkb;
    reg ace;    // age_change_enable
    reg te;     // takeover_enable
    reg preg;   // player_reg (0 = P1, 1 = P2)
    reg ftreg;  // first_turn_reg
    wire [2:0] state;

    cell_fsm main (
        .clka(clka),
        .clkb(clkb),
        .age_change_enable(ace),
        .takeover_enable(te),
        .player_reg(preg),
        .first_turn_reg(ftreg),
        .state(state)
    );

    // Two-phase clock: clka computes next state, clkb latches it
    task clock_cycle;
    begin
        clka = 0; clkb = 0; #10;
        clka = 1; clkb = 0; #10;
        clka = 0; clkb = 0; #10;
        clka = 0; clkb = 1; #10;
    end
    endtask

    initial begin
        // Let the cell settle in its initial state
        clock_cycle;

        // Clear all control signals
        te = 0; ace = 0; clock_cycle;

        // Test Player 1: claim empty cell, age up through explosion
        ftreg = 1; preg = 0; clock_cycle;  // set up for first turn
        ace = 1; te = 0; clock_cycle;      // claim cell -> P1_1
        ftreg = 0; clock_cycle;            // no longer first turn
        ace = 1; clock_cycle;              // age up -> P1_2
        ace = 0; clock_cycle;              // idle
        te = 1; clock_cycle;               // takeover (same player) -> P1_3
        ace = 1; te = 0; clock_cycle;      // age up -> EXP
        ace = 1; clock_cycle;              // should return to EMPTY
        
        // Reset signals
        te = 0; ace = 0; clock_cycle;

        // Test Player 2: same sequence
        ftreg = 1; preg = 1; clock_cycle;  // first turn, player 2
        ace = 1; te = 0; clock_cycle;      // claim cell -> P2_1
        ftreg = 0; clock_cycle;
        ace = 1; clock_cycle;              // -> P2_2
        ace = 0; clock_cycle;
        te = 1; clock_cycle;               // -> P2_3
        ace = 1; te = 0; clock_cycle;      // -> EXP
        ace = 1; clock_cycle;              // -> EMPTY

        // Done
        te = 0; ace = 0; clock_cycle;
    end

endmodule
