module serv_rf_ram (
    input  logic       i_clk,
    input  logic [8:0] i_waddr,
    input  logic [1:0] i_wdata,
    input  logic       i_wen,
    input  logic [8:0] i_raddr,
    input  logic       i_ren,
    output logic [1:0] o_rdata
);

    logic [1:0] rf_mem [0:511];
    logic [1:0] rf_rdata_raw;
    logic       regzero;

    initial begin
        for (int i = 0; i < 512; i++) begin
            rf_mem[i] = 2'b00;
        end
    end

    always_ff @(posedge i_clk) begin
        if (i_wen)
            rf_mem[i_waddr] <= i_wdata;
        rf_rdata_raw <= i_ren ? rf_mem[i_raddr] : 2'b00;
        regzero      <= !(|i_raddr[8:4]);
    end

    assign o_rdata = rf_rdata_raw & ~{2{regzero}};

endmodule
