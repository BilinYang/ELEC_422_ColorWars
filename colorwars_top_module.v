module top_module (
    input  wire       clka,
    input  wire       clkb,
    input  wire       reset,
    input  wire [4:0] row,
    input  wire [4:0] column,
    input  wire       confirm,
    input  wire       cell_is_empty,
    input  wire       cell_is_other_player,
    input  wire       explode_flag,
    input  wire       first_turn_flag,
    input  wire       iterate_done,
    output wire       win_register,
    output wire       start_iteration,
    output wire       clear_errors,
    output wire       show_empty_error,
    output wire       show_owner_error,
    output wire       multiple_inputs_error,
    output wire [2:0] state,
    output wire [3:0] add_result_out
);

    colorwars_fsm fsm (
        .clk_a_in(clka),
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

    colorwars_dp dp (
        .clka_in(clka),
        .clkb_in(clkb),
        .reset_in(reset),
        .row_in(row),
        .column_in(column),
        .state_in(state),
        .win_register_out(win_register)
    );

endmodule