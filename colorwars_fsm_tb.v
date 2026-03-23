`timescale 1ns / 1ps

// Testbench for game_fsm
// Simulates player inputs and datapath feedback to verify FSM behavior

module tb_game_fsm;

    reg clk_a;
    reg reset;

    // Simulated player inputs
    reg win_register;
    reg [4:0] row;
    reg [4:0] column;
    reg confirm;

    // Simulated feedback from datapath
    reg cell_is_empty;
    reg cell_is_other_player;
    reg explode_flag;
    reg first_turn_flag;
    reg iterate_done;

    // FSM outputs
    wire start_iteration;
    wire clear_errors;
    wire show_empty_error;
    wire show_owner_error;
    wire multiple_inputs_error;
    wire [2:0] state;

    colorwars_fsm uut (
        .clk_a_in(clk_a),
        .reset_in(reset),
        .win_register_in(win_register),
        .row_in(row),
        .column_in(column),
        .confirm_in(confirm),
        .cell_is_empty_in(cell_is_empty),
        .cell_is_other_player_in(cell_is_other_player),
        .explode_flag_in(explode_flag),
        .first_turn_flag_in(first_turn_flag),
        .iterate_done_in(iterate_done),
        .start_iteration_out(start_iteration),
        .clear_errors_out(clear_errors),
        .show_empty_error_out(show_empty_error),
        .show_owner_error_out(show_owner_error),
        .multiple_inputs_error_out(multiple_inputs_error),
        .state_out(state)
    );

    // 10ns clock period
    initial clk_a = 0;
    always #5 clk_a = ~clk_a;

    initial begin
        // Start with reset asserted
        reset = 1;
        win_register = 0;
        row = 0;
        column = 0;
        confirm = 0;
        cell_is_empty = 0;
        cell_is_other_player = 0;
        explode_flag = 0;
        first_turn_flag = 0;
        iterate_done = 0;

        #12;
        reset = 0;

        // Test 1: Player selects cell (0,0) and confirms
        row = 5'b00001;
        column = 5'b00001;
        confirm = 1;
        first_turn_flag = 1;
        #10;

        // Test 2: Selecting empty cell after first turn should show error
        cell_is_empty = 1;
        #10;
        cell_is_empty = 0;

        // Test 3: Valid move goes to iteration
        first_turn_flag = 0;
        #10;

        // Test 4: Chain reaction - explosion triggers another pass
        iterate_done = 0;
        explode_flag = 1;
        #10;
        iterate_done = 1;
        #10;
        iterate_done = 0;
        explode_flag = 0;  // no more explosions, should go back to IDLE
        #10;

        // Test 5: Win condition ends the game
        win_register = 1;
        #10;
        win_register = 0;

        #20;
        $finish;
    end

    // Monitor state changes for debugging
    initial begin
        $monitor("t=%0t | state=%0d | start_iter=%b | empty_err=%b | owner_err=%b | multi_err=%b",
                 $time, state, start_iteration, show_empty_error, show_owner_error, multiple_inputs_error);
    end

endmodule