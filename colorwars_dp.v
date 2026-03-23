module colorwars_dp (
    input wire clka_in, 
    input wire clkb_in, 
    input wire reset_in,
    input wire row_in,
    input wire column_in,
    input wire confirm_in,
    input wire [2:0] state_in,
    output reg win_register_out,
    output reg is_empty_error
); 
    reg [74:0] cell_states; 
    wire [74:0] cell_states_wire; 
    reg [24:0] age_change_enable; 
    reg [24:0] takeover_enable; 


    genvar r, c; 
    generate
        for (r=0; r<5; r=r+1) begin: GEN_ROW
            for (c=0; c<5; c=c+1) begin: GEN_COL
                localparam integer i = 5*r + c; 
                wire [2:0] cell_state; 
                assign cell_states_wire[(3*IDX)+2 : (3*IDX)] = cell_state;
                
                cell_fsm u_cell (
                    .clka_in(clka_in),
                    .clkb_in(clkb_in),
                    .age_change_enable_in(age_change_enable[i]),
                    .takeover_enable_in(takeover_enable[i]),
                    .player_reg_in(player_reg),
                    .first_turn_reg_in(first_turn_reg),
                    .state_out(cell_state)
                );
            end
        end
    endgenerate

    always @(negedge clka_in)
    begin
        if (reset_in) begin
            cell_states <= 75'b0; 
        end
        else begin
            cell_states <= cell_states_wire; 
        end
    end

    always @(negedge clkb_in)
    begin
        
        if (cell_states[(5*row + column)*3:((5*row + column)*3) + 2] == 3'b000) begin
            is_empty_error = 1'b1;
        end
            

    always @(negedge clkb_in) 
    begin 
        if (reset_in) begin
            win_register_out <= 1'b0;
        end
    end

endmodule