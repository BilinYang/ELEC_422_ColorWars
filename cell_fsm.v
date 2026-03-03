// Cell FSM for Color Wars game
// Each cell on the 5x5 grid is controlled by its own instance of this module.
// The cell tracks ownership (Player 1 or 2) and age (1, 2, or 3). When age
// reaches 3 and the cell is activated again, it explodes and affects neighbors.

module cell_fsm(
	input clka, clkb,
	input age_change_enable,  // increment age, keep same player (player clicked this cell)
	input takeover_enable,    // increment age and change owner (neighbor exploded)
	input player_reg,         // 0 = Player 1's turn, 1 = Player 2's turn
	input first_turn_reg,     // high during the very first turn of the game
	output reg [2:0] state
);

// State encoding: bits [2:1] = age (0-3), bit [0] = player (0=P1, 1=P2)
// We use specific encodings to make LED display decoding easier
parameter EMPTY = 3'b000;  // unowned, no player
parameter P1_1  = 3'b010;  // Player 1, age 1
parameter P1_2  = 3'b100;  // Player 1, age 2
parameter P1_3  = 3'b110;  // Player 1, age 3 (will explode on next hit)
parameter P2_1  = 3'b011;  // Player 2, age 1
parameter P2_2  = 3'b101;  // Player 2, age 2
parameter P2_3  = 3'b111;  // Player 2, age 3 (will explode on next hit)
parameter EXP   = 3'b001;  // explosion state (lasts one cycle, then goes empty)

reg [2:0] temp_state;

// Compute next state on clka falling edge
always @(negedge clka) begin
	case (state)
		// Empty cell can be claimed on first turn, or taken over by explosion
		EMPTY: begin
			if ((first_turn_reg & age_change_enable) == 1) begin
				if (player_reg == 0) temp_state = P1_1;
				else if (player_reg == 1) temp_state = P2_1;
			end
			if (takeover_enable) begin
				if (player_reg == 0) temp_state = P1_1;
				else temp_state = P2_1;
			end
		end

		// Player 1 cells: age up on click, or get taken over by Player 2's explosion
		P1_1: begin
			if (age_change_enable) temp_state = P1_2;
			else if (takeover_enable && player_reg == 0) temp_state = P1_2;
			else if (takeover_enable && player_reg == 1) temp_state = P2_2;
		end
		
		P1_2: begin
			if (age_change_enable) temp_state = P1_3;
			else if (takeover_enable && player_reg == 0) temp_state = P1_3;
			else if (takeover_enable && player_reg == 1) temp_state = P2_3;
		end
		
		P1_3: begin
			// Age 3 cells explode when hit again
			if (age_change_enable || takeover_enable) temp_state = EXP;
		end
		
		// Player 2 cells: same logic, mirrored
		P2_1: begin
			if (age_change_enable) temp_state = P2_2;
			else if (takeover_enable && player_reg == 0) temp_state = P1_2;
			else if (takeover_enable && player_reg == 1) temp_state = P2_2;
		end

		P2_2: begin
			if (age_change_enable) temp_state = P2_3;
			else if (takeover_enable && player_reg == 0) temp_state = P1_3;
			else if (takeover_enable && player_reg == 1) temp_state = P2_3;
		end

		P2_3: begin
			if (age_change_enable || takeover_enable) temp_state = EXP;
		end

		// Explosion is transient: clears to empty on the next cycle
		EXP: begin
			temp_state = EMPTY;
		end

		default: temp_state = EMPTY;

	endcase

end

// Latch state on clkb falling edge (two-phase clocking for glitch-free updates)
always @(negedge clkb) begin
	state = temp_state;
end

endmodule