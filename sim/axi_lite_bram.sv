// ============================================================================
// axi_lite_bram.sv
// Memoria RAM/ROM Unificada de 16 KB (4096 x 32 bits) com Interface Escrava
// SystemVerilog AXI4-Lite (structs axi_lite_mosi_t / axi_lite_miso_t).
// Inicializada no bitstream via firmware.hex.
//
// Conformidade AMBA AXI4-Lite (Secao A3.3.1):
//   - `bvalid` so eh ativado APOS a conclusao dos handshakes `AW` e `W`
//   - `rvalid` so eh ativado APOS a conclusao do handshake `AR`
// ============================================================================
`default_nettype none

module axi_lite_bram
    import axi_lite_pkg::*;
(
    input  logic           s_axi_aclk,
    input  logic           s_axi_aresetn,

    // Barramento AXI4-Lite Slave (Structs SystemVerilog)
    input  axi_lite_mosi_t s_axi_mosi,
    output axi_lite_miso_t s_axi_miso
);

    assign s_axi_miso.bresp = 2'b00; // OKAY
    assign s_axi_miso.rresp = 2'b00; // OKAY

    // Block RAM de 16 KB (4096 palavras de 32 bits)
    logic [31:0] bram [0:4095];

    initial begin
        $readmemh("firmware.hex", bram);
    end

    logic        write_req;
    logic        read_req;
    logic [11:0] bram_addr;

    assign write_req = !s_axi_miso.awready && s_axi_mosi.awvalid && s_axi_mosi.wvalid && !s_axi_miso.bvalid;
    assign read_req  = !s_axi_miso.arready && s_axi_mosi.arvalid && !s_axi_miso.rvalid && !write_req && !s_axi_miso.awready;
    assign bram_addr = write_req ? s_axi_mosi.awaddr[13:2] : s_axi_mosi.araddr[13:2];

    // Acesso sincrono a Block RAM (inferencia de RAMB16BWER no Spartan-6)
    always_ff @(posedge s_axi_aclk) begin
        if (write_req) begin
            if (s_axi_mosi.wstrb[0]) bram[bram_addr][7:0]   <= s_axi_mosi.wdata[7:0];
            if (s_axi_mosi.wstrb[1]) bram[bram_addr][15:8]  <= s_axi_mosi.wdata[15:8];
            if (s_axi_mosi.wstrb[2]) bram[bram_addr][23:16] <= s_axi_mosi.wdata[23:16];
            if (s_axi_mosi.wstrb[3]) bram[bram_addr][31:24] <= s_axi_mosi.wdata[31:24];
        end
        if (read_req) begin
            s_axi_miso.rdata <= bram[bram_addr];
        end
    end

    // Controle de Handshake AXI4-Lite estritamente conforme AMBA AXI4-Lite A3.3.1
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_miso.awready <= 1'b0;
            s_axi_miso.wready  <= 1'b0;
            s_axi_miso.bvalid  <= 1'b0;
            s_axi_miso.arready <= 1'b0;
            s_axi_miso.rvalid  <= 1'b0;
        end else begin
            // ----------------------------------------------------------------
            // Canal de Escrita:
            //   Ciclo 1: Aceita AW e W (awready=1, wready=1)
            //   Ciclo 2: Concluido handshake AW/W, levanta BVALID=1
            // ----------------------------------------------------------------
            if (write_req) begin
                s_axi_miso.awready <= 1'b1;
                s_axi_miso.wready  <= 1'b1;
            end else if (s_axi_miso.awready && s_axi_mosi.awvalid && s_axi_miso.wready && s_axi_mosi.wvalid) begin
                s_axi_miso.awready <= 1'b0;
                s_axi_miso.wready  <= 1'b0;
                s_axi_miso.bvalid  <= 1'b1;
            end else begin
                s_axi_miso.awready <= 1'b0;
                s_axi_miso.wready  <= 1'b0;
                if (s_axi_miso.bvalid && s_axi_mosi.bready)
                    s_axi_miso.bvalid <= 1'b0;
            end

            // ----------------------------------------------------------------
            // Canal de Leitura:
            //   Ciclo 1: Aceita AR (arready=1) e le da BRAM
            //   Ciclo 2: Concluido handshake AR, levanta RVALID=1 com RDATA estavel
            // ----------------------------------------------------------------
            if (read_req) begin
                s_axi_miso.arready <= 1'b1;
            end else if (s_axi_miso.arready && s_axi_mosi.arvalid) begin
                s_axi_miso.arready <= 1'b0;
                s_axi_miso.rvalid  <= 1'b1;
            end else begin
                s_axi_miso.arready <= 1'b0;
                if (s_axi_miso.rvalid && s_axi_mosi.rready)
                    s_axi_miso.rvalid <= 1'b0;
            end
        end
    end

endmodule
`default_nettype wire
