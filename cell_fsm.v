`timescale 1ns / 1ps

// Per-cell state machine used by Color Wars.
//
// There’s one of these for each of the 25 grid cells. It keeps track of:
//   - who owns the cell (P1 vs P2)
//   - the “age” counter (1..3)
//
// When a cell at age 3 gets hit again (either by a click or a takeover), it
// briefly enters EXP, then clears back to EMPTY on the next cycle.
//
// Implementation notes:
//   - Two-phase clocking: clka computes the next state, clkb latches it.
//   - reset_in clears everything back to EMPTY.

module cell_fsm (
    input  wire       clka_in,
    input  wire       clkb_in,
    input  wire       reset_in,
    input  wire       age_change_enable_in,  // player clicked this cell
    input  wire       takeover_enable_in,    // neighbor exploded into this cell
    input  wire       player_reg_in,         // 0 = Player 1's turn, 1 = Player 2's turn
    input  wire       first_turn_reg_in,     // high during the first round of the game
    output reg  [2:0] state_out
);

    // Encoding: bit[0] is the player (0=P1, 1=P2); bits[2:1] carry the age.
    // This layout matches the LED decode logic used elsewhere.
    parameter EMPTY = 3'b000;  // unowned
    parameter P1_1  = 3'b010;  // Player 1, age 1
    parameter P1_2  = 3'b100;  // Player 1, age 2
    parameter P1_3  = 3'b110;  // Player 1, age 3 (explodes on next hit)
    parameter P2_1  = 3'b011;  // Player 2, age 1
    parameter P2_2  = 3'b101;  // Player 2, age 2
    parameter P2_3  = 3'b111;  // Player 2, age 3 (explodes on next hit)
    parameter EXP   = 3'b001;  // explosion (transient, clears to EMPTY next cycle)

    reg [2:0] temp_state;

    // Phase A (clka): work out the next state.
    always @(negedge clka_in or posedge reset_in) begin
        if (reset_in) begin
            temp_state = EMPTY;
        end
        else begin
            temp_state = state_out;  // default: hold

            case (state_out)
                EMPTY: begin
                    // On the first round, an empty cell can be claimed.
                    if ((first_turn_reg_in & age_change_enable_in) == 1'b1) begin
                        if (player_reg_in == 1'b0) temp_state = P1_1;
                        else                        temp_state = P2_1;
                    end
                    // Neighbor explosion can also claim an empty cell.
                    if (takeover_enable_in) begin
                        if (player_reg_in == 1'b0) temp_state = P1_1;
                        else                        temp_state = P2_1;
                    end
                end

                // Player 1 cells
                P1_1: begin
                    if (age_change_enable_in) temp_state = P1_2;
                    else if (takeover_enable_in && player_reg_in == 1'b0) temp_state = P1_2;
                    else if (takeover_enable_in && player_reg_in == 1'b1) temp_state = P2_2;
                end

                P1_2: begin
                    if (age_change_enable_in) temp_state = P1_3;
                    else if (takeover_enable_in && player_reg_in == 1'b0) temp_state = P1_3;
                    else if (takeover_enable_in && player_reg_in == 1'b1) temp_state = P2_3;
                end

                P1_3: begin
                    if (age_change_enable_in || takeover_enable_in) temp_state = EXP;
                end

                // Player 2 cells
                P2_1: begin
                    if (age_change_enable_in) temp_state = P2_2;
                    else if (takeover_enable_in && player_reg_in == 1'b0) temp_state = P1_2;
                    else if (takeover_enable_in && player_reg_in == 1'b1) temp_state = P2_2;
                end

                P2_2: begin
                    if (age_change_enable_in) temp_state = P2_3;
                    else if (takeover_enable_in && player_reg_in == 1'b0) temp_state = P1_3;
                    else if (takeover_enable_in && player_reg_in == 1'b1) temp_state = P2_3;
                end

                P2_3: begin
                    if (age_change_enable_in || takeover_enable_in) temp_state = EXP;
                end

                // EXP is a one-cycle transient; it clears to EMPTY right after.
                EXP: begin
                    temp_state = EMPTY;
                end

                default: temp_state = EMPTY;
            endcase
        end
    end

    // Phase B (clkb): latch the computed state.
    always @(negedge clkb_in or posedge reset_in) begin
        if (reset_in)
            state_out <= EMPTY;
        else
            state_out <= temp_state;
    end

endmodule
