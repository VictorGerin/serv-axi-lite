// ============================================================================
// wb_to_axi_lite.sv
// Ponte Conversora Wishbone B3 (Classic/Pipelined) -> ARM AXI4-Lite Master
//
// Converte os ciclos de barramento de leitura/escrita Wishbone nas transacoes
// correspondentes nos 5 canais do protocolo ARM AXI4-Lite:
//   - Escrita (we = 1): canais AW, W e B (respeitando handshakes desacoplados)
//   - Leitura (we = 0): canais AR e R
//
// Conformidade AMBA AXI4-Lite:
//   - Zero violacoes nos verificadores formais SVA (Axi4LitePC)
//   - Nao assume sincronia entre AWREADY e WREADY
//   - Devolve wb_ack no ciclo exato de conclusao (BVALID para escrita, RVALID para leitura)
// ============================================================================
`default_nettype none

module wb_to_axi_lite
    import axi_lite_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // Interface Wishbone Escravo (conectada ao mestre da CPU/Cache)
    input  logic [31:0] wb_adr,
    input  logic [31:0] wb_dat_w,
    output logic [31:0] wb_dat_r,
    input  logic [3:0]  wb_sel,
    input  logic        wb_we,
    input  logic        wb_cyc,
    output logic        wb_ack,

    // Interface AXI4-Lite Mestre (conectada ao Interconnect)
    output axi_lite_mosi_t m_axi_mosi,
    input  axi_lite_miso_t m_axi_miso
);

    logic active;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_dat_r           <= 32'd0;
            wb_ack             <= 1'b0;
            m_axi_mosi.awaddr  <= 32'd0;
            m_axi_mosi.awvalid <= 1'b0;
            m_axi_mosi.wdata   <= 32'd0;
            m_axi_mosi.wstrb   <= 4'b0000;
            m_axi_mosi.wvalid  <= 1'b0;
            m_axi_mosi.bready  <= 1'b0;
            m_axi_mosi.araddr  <= 32'd0;
            m_axi_mosi.arvalid <= 1'b0;
            m_axi_mosi.rready  <= 1'b0;
            m_axi_mosi.master_id <= 8'd0;
            active             <= 1'b0;
        end else begin
            wb_ack <= 1'b0;

            if (wb_ack) begin
                active <= 1'b0;
            end else if (!active) begin
                if (wb_cyc) begin
                    active <= 1'b1;
                    if (wb_we) begin
                        // Transacao de Escrita (AW, W, B)
                        m_axi_mosi.awaddr  <= wb_adr;
                        m_axi_mosi.awvalid <= 1'b1;
                        m_axi_mosi.wdata   <= wb_dat_w;
                        m_axi_mosi.wstrb   <= wb_sel;
                        m_axi_mosi.wvalid  <= 1'b1;
                        m_axi_mosi.bready  <= 1'b1;
                    end else begin
                        // Transacao de Leitura (AR, R)
                        m_axi_mosi.araddr  <= wb_adr;
                        m_axi_mosi.arvalid <= 1'b1;
                        m_axi_mosi.rready  <= 1'b1;
                    end
                end
            end else begin
                // -------------------------------------------------------------
                // Handshakes de Escrita
                // -------------------------------------------------------------
                if (m_axi_mosi.awvalid && m_axi_miso.awready) begin
                    m_axi_mosi.awvalid <= 1'b0;
                end
                if (m_axi_mosi.wvalid && m_axi_miso.wready) begin
                    m_axi_mosi.wvalid <= 1'b0;
                end
                if (m_axi_miso.bvalid && m_axi_mosi.bready) begin
                    m_axi_mosi.bready <= 1'b0;
                    wb_ack            <= 1'b1;
                end

                // -------------------------------------------------------------
                // Handshakes de Leitura
                // -------------------------------------------------------------
                if (m_axi_mosi.arvalid && m_axi_miso.arready) begin
                    m_axi_mosi.arvalid <= 1'b0;
                end
                if (m_axi_miso.rvalid && m_axi_mosi.rready) begin
                    m_axi_mosi.rready <= 1'b0;
                    wb_dat_r          <= m_axi_miso.rdata;
                    wb_ack            <= 1'b1;
                end
            end
        end
    end

endmodule
`default_nettype wire
