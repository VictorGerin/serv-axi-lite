module serv_wrapper
    import wb_pkg::*;
#(
    parameter bit          WITH_CSR     = 1'b1,
    parameter logic [31:0] RESET_PC     = 32'h0000_0000,
    parameter string       RESET_STRATEGY = "MINI"
)(
    input  logic       clk,
    input  logic       i_rst,
    input  logic       i_timer_irq,

    // Interface Register File
    output logic       o_rf_rreq,
    output logic       o_rf_wreq,
    input  logic       i_rf_ready,
    output logic [4:0] o_wreg0,
    output logic [4:0] o_wreg1,
    output logic       o_wen0,
    output logic       o_wen1,
    output logic       o_wdata0,
    output logic       o_wdata1,
    output logic [4:0] o_rreg0,
    output logic [4:0] o_rreg1,
    input  logic       i_rdata0,
    input  logic       i_rdata1,

    // Wishbone iBus
    output wb_mosi_t   o_ibus_mosi,
    input  wb_miso_t   i_ibus_miso,

    // Wishbone dBus
    output wb_mosi_t   o_dbus_mosi,
    input  wb_miso_t   i_dbus_miso
);

    assign o_ibus_mosi.dat = 32'd0;
    assign o_ibus_mosi.sel = 4'b1111;
    assign o_ibus_mosi.we  = 1'b0;

    serv_top #(
        .WITH_CSR       (WITH_CSR),
        .RESET_PC       (RESET_PC),
        .RESET_STRATEGY (RESET_STRATEGY),
        .PRE_REGISTER   (1),
        .COMPRESSED     (1'b0),
        .ALIGN          (1'b0),
        .W              (1)
    ) u_serv_top (
        .clk          (clk),
        .i_rst        (i_rst),
        .i_timer_irq  (i_timer_irq),

        .o_rf_rreq    (o_rf_rreq),
        .o_rf_wreq    (o_rf_wreq),
        .i_rf_ready   (i_rf_ready),
        .o_wreg0      (o_wreg0),
        .o_wreg1      (o_wreg1),
        .o_wen0       (o_wen0),
        .o_wen1       (o_wen1),
        .o_wdata0     (o_wdata0),
        .o_wdata1     (o_wdata1),
        .o_rreg0      (o_rreg0),
        .o_rreg1      (o_rreg1),
        .i_rdata0     (i_rdata0),
        .i_rdata1     (i_rdata1),

        .o_ibus_adr   (o_ibus_mosi.adr),
        .o_ibus_cyc   (o_ibus_mosi.cyc),
        .i_ibus_rdt   (i_ibus_miso.rdt),
        .i_ibus_ack   (i_ibus_miso.ack),

        .o_dbus_adr   (o_dbus_mosi.adr),
        .o_dbus_dat   (o_dbus_mosi.dat),
        .o_dbus_sel   (o_dbus_mosi.sel),
        .o_dbus_we    (o_dbus_mosi.we),
        .o_dbus_cyc   (o_dbus_mosi.cyc),
        .i_dbus_rdt   (i_dbus_miso.rdt),
        .i_dbus_ack   (i_dbus_miso.ack),

        .o_ext_funct3 (),
        .i_ext_ready  (1'b0),
        .i_ext_rd     (32'd0),
        .o_ext_rs1    (),
        .o_ext_rs2    (),
        .o_mdu_valid  ()
    );

endmodule
