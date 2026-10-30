// ============================================================================
// serv_top_axi.sv
// Processador RISC-V SERV encapsulado com interface SystemVerilog AXI4-Lite
// Master (usando structs axi_lite_mosi_t e axi_lite_miso_t).
// ============================================================================
`default_nettype none

module serv_top_axi
    import axi_lite_pkg::*;
#(
    parameter logic [31:0] RESET_PC     = 32'h0000_0000,
    parameter int          ICACHE_WORDS = 0
) (
    input  logic           aclk,
    input  logic           aresetn,
    input  logic           i_timer_irq,

    // Barramentos AXI4-Lite Master (Structs SystemVerilog): iBus e dBus independentes
    output axi_lite_mosi_t m_axi_ibus_mosi,
    input  axi_lite_miso_t m_axi_ibus_miso,
    output axi_lite_mosi_t m_axi_dbus_mosi,
    input  axi_lite_miso_t m_axi_dbus_miso
);

    logic i_rst;
    assign i_rst = ~aresetn;

    // ------------------------------------------------------------------------
    // Sinais internos Wishbone (iBus e dBus) do nucleo SERV
    // ------------------------------------------------------------------------
    logic [31:0] cpu_ibus_adr;
    logic        cpu_ibus_cyc;
    logic [31:0] cpu_ibus_rdt;
    logic        cpu_ibus_ack;

    // Sinais de instrucao conectados ao arbitro AXI (diretos ou via I-Cache)
    logic [31:0] axi_ibus_adr;
    logic        axi_ibus_cyc;
    logic [31:0] axi_ibus_rdt;
    logic        axi_ibus_ack;

    generate
        if (ICACHE_WORDS > 0) begin : gen_icache
            serv_icache #(
                .NUM_WORDS (ICACHE_WORDS)
            ) u_serv_icache (
                .clk     (aclk),
                .rst     (i_rst),
                .cpu_adr (cpu_ibus_adr),
                .cpu_cyc (cpu_ibus_cyc),
                .cpu_rdt (cpu_ibus_rdt),
                .cpu_ack (cpu_ibus_ack),
                .mem_adr (axi_ibus_adr),
                .mem_cyc (axi_ibus_cyc),
                .mem_rdt (axi_ibus_rdt),
                .mem_ack (axi_ibus_ack)
            );
        end else begin : gen_no_icache
            // Bypass completo: conexao 100% direta e identica ao circuito original
            assign axi_ibus_adr = cpu_ibus_adr;
            assign axi_ibus_cyc = cpu_ibus_cyc;
            assign cpu_ibus_rdt = axi_ibus_rdt;
            assign cpu_ibus_ack = axi_ibus_ack;
        end
    endgenerate

    logic [31:0] wb_dbus_adr;
    logic [31:0] wb_dbus_dat;
    logic [3:0]  wb_dbus_sel;
    logic        wb_dbus_we;
    logic        wb_dbus_cyc;
    logic [31:0] wb_dbus_rdt;
    logic        wb_dbus_ack;

    // ------------------------------------------------------------------------
    // Banco de Registradores em SRAM (512 x 2 bits) + Interface RF do SERV
    // ------------------------------------------------------------------------
    logic       rf_wreq;
    logic       rf_rreq;
    logic [4:0] wreg0;
    logic [4:0] wreg1;
    logic       wen0;
    logic       wen1;
    logic       wdata0;
    logic       wdata1;
    logic [4:0] rreg0;
    logic [4:0] rreg1;
    logic       rf_ready;
    logic       rdata0;
    logic       rdata1;

    logic       rgnt;
    logic [4:0] rcnt;
    logic       rtrig1;
    logic [4:0] wcnt;
    assign wcnt = rcnt - 5'd4;

    logic [1:0] wdata0_r;
    logic [2:0] wdata1_r;
    logic       wen0_r;
    logic       wen1_r;
    logic       wtrig0;
    logic       wtrig1;
    assign wtrig0 = rtrig1;
    assign wtrig1 = wcnt[0];

    logic [1:0] wdata;
    logic [4:0] wreg;
    logic [8:0] waddr;
    logic       wen;
    assign wdata = wtrig1 ? wdata1_r[1:0] : wdata0_r;
    assign wreg  = wtrig1 ? wreg1 : wreg0;
    assign waddr = {wreg, wcnt[4:1]};
    assign wen   = (wtrig0 & wen0_r) | (wtrig1 & wen1_r);

    logic       rtrig0;
    logic [4:0] rreg;
    logic [8:0] raddr;
    assign rtrig0 = rcnt[0];
    assign rreg   = rtrig0 ? rreg1 : rreg0;
    assign raddr  = {rreg, rcnt[4:1]};

    logic [1:0] rdata0_sh;
    logic       rdata1_sh;
    logic       rgate;
    logic       rreq_r;
    logic       ren;
    assign ren = rgate;

    logic [1:0] rf_mem [0:511];
    logic [1:0] rf_rdata_raw;
    logic       regzero;

    initial begin
        for (int i = 0; i < 512; i++) begin
            rf_mem[i] = 2'b00;
        end
    end

    always_ff @(posedge aclk) begin
        if (wen)
            rf_mem[waddr] <= wdata;
        rf_rdata_raw <= ren ? rf_mem[raddr] : 2'b00;
        regzero      <= !(|raddr[8:4]);
    end

    logic [1:0] rf_rdata;
    assign rf_rdata = rf_rdata_raw & ~{2{regzero}};

    assign rf_ready = rgnt | rf_wreq;
    assign rdata0   = rdata0_sh[0];
    assign rdata1   = rtrig1 ? rf_rdata[0] : rdata1_sh;

    always_ff @(posedge aclk) begin
        if (wcnt[0]) begin
            wen0_r <= wen0;
            wen1_r <= wen1;
        end
        wdata0_r <= {wdata0, wdata0_r[1]};
        wdata1_r <= {wdata1, wdata1_r[2:1]};

        if (rtrig1)
            rdata1_sh <= rf_rdata[1];

        if ((&rcnt) | rf_rreq)
            rgate <= rf_rreq;

        rtrig1 <= rtrig0;
        rcnt   <= rcnt + 5'd1;
        if (rf_rreq | rf_wreq)
            rcnt <= {3'b000, rf_wreq, 1'b0};

        rreq_r <= rf_rreq;
        rgnt   <= rreq_r;

        rdata0_sh <= {1'b0, rdata0_sh[1]};
        if (rtrig0)
            rdata0_sh <= rf_rdata;

        if (i_rst) begin
            rgate  <= 1'b0;
            rgnt   <= 1'b0;
            rreq_r <= 1'b0;
            rcnt   <= 5'd0;
        end
    end

    // ------------------------------------------------------------------------
    // Instancia do Nucleo SERV Oficial (`src/rtl/serv/rtl/serv_top.v`)
    // ------------------------------------------------------------------------
    serv_top #(
        .RESET_PC       (RESET_PC),
        .PRE_REGISTER   (1),
        .RESET_STRATEGY ("MINI"),
        .WITH_CSR       (0),
        .DEBUG          (1'b0),
        .MDU            (1'b0),
        .COMPRESSED     (1'b0),
        .ALIGN          (1'b0),
        .W              (1)
    ) u_serv_top (
        .clk          (aclk),
        .i_rst        (i_rst),
        .i_timer_irq  (i_timer_irq),

        .o_rf_rreq    (rf_rreq),
        .o_rf_wreq    (rf_wreq),
        .i_rf_ready   (rf_ready),
        .o_wreg0      (wreg0),
        .o_wreg1      (wreg1),
        .o_wen0       (wen0),
        .o_wen1       (wen1),
        .o_wdata0     (wdata0),
        .o_wdata1     (wdata1),
        .o_rreg0      (rreg0),
        .o_rreg1      (rreg1),
        .i_rdata0     (rdata0),
        .i_rdata1     (rdata1),

        .o_ibus_adr   (cpu_ibus_adr),
        .o_ibus_cyc   (cpu_ibus_cyc),
        .i_ibus_rdt   (cpu_ibus_rdt),
        .i_ibus_ack   (cpu_ibus_ack),

        .o_dbus_adr   (wb_dbus_adr),
        .o_dbus_dat   (wb_dbus_dat),
        .o_dbus_sel   (wb_dbus_sel),
        .o_dbus_we    (wb_dbus_we),
        .o_dbus_cyc   (wb_dbus_cyc),
        .i_dbus_rdt   (wb_dbus_rdt),
        .i_dbus_ack   (wb_dbus_ack),

        .o_ext_funct3 (),
        .i_ext_ready  (1'b0),
        .i_ext_rd     (32'd0),
        .o_ext_rs1    (),
        .o_ext_rs2    (),
        .o_mdu_valid  ()
    );

    // ------------------------------------------------------------------------
    // Pontes Conversoras Wishbone -> AXI4-Lite Master (iBus e dBus desacoplados)
    // ------------------------------------------------------------------------
    // Ponte de Instrucao (iBus -> AXI Master): Leitura pura
    wb_to_axi_lite u_wb2axi_ibus (
        .clk        (aclk),
        .rst_n      (aresetn),
        .wb_adr     (axi_ibus_adr),
        .wb_dat_w   (32'd0),
        .wb_dat_r   (axi_ibus_rdt),
        .wb_sel     (4'b1111),
        .wb_we      (1'b0),
        .wb_cyc     (axi_ibus_cyc),
        .wb_ack     (axi_ibus_ack),
        .m_axi_mosi (m_axi_ibus_mosi),
        .m_axi_miso (m_axi_ibus_miso)
    );

    // Ponte de Dados (dBus -> AXI Master): Leitura e Escrita
    wb_to_axi_lite u_wb2axi_dbus (
        .clk        (aclk),
        .rst_n      (aresetn),
        .wb_adr     (wb_dbus_adr),
        .wb_dat_w   (wb_dbus_dat),
        .wb_dat_r   (wb_dbus_rdt),
        .wb_sel     (wb_dbus_sel),
        .wb_we      (wb_dbus_we),
        .wb_cyc     (wb_dbus_cyc),
        .wb_ack     (wb_dbus_ack),
        .m_axi_mosi (m_axi_dbus_mosi),
        .m_axi_miso (m_axi_dbus_miso)
    );

endmodule
`default_nettype wire
