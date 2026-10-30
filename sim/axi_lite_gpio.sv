// ============================================================================
// axi_lite_gpio.sv
// Periferico Escravo SystemVerilog AXI4-Lite GPIO:
//   - 0x00: GPIO_DATA (Leitura/Escrita de 32 bits)
//   - 0x04: GPIO_TRI  (Direcao: 0=Saida, 1=Entrada)
//
// Conformidade AMBA AXI4-Lite (Secao A3.3.1):
//   - `bvalid` so eh ativado APOS a conclusao dos handshakes `AW` e `W`
//   - `rvalid` so eh ativado APOS a conclusao do handshake `AR`
// ============================================================================
`default_nettype none

module axi_lite_gpio
    import axi_lite_pkg::*;
(
    input  logic           s_axi_aclk,
    input  logic           s_axi_aresetn,

    // Barramento AXI4-Lite Slave (Structs SystemVerilog)
    input  axi_lite_mosi_t s_axi_mosi,
    output axi_lite_miso_t s_axi_miso,

    // Pinos Fisicos de GPIO
    input  logic [31:0]    gpio_io_i,
    output logic [31:0]    gpio_io_o,
    output logic [31:0]    gpio_io_t
);

    assign s_axi_miso.bresp = 2'b00; // OKAY
    assign s_axi_miso.rresp = 2'b00; // OKAY

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_miso.awready <= 1'b0;
            s_axi_miso.wready  <= 1'b0;
            s_axi_miso.bvalid  <= 1'b0;
            s_axi_miso.arready <= 1'b0;
            s_axi_miso.rvalid  <= 1'b0;
            s_axi_miso.rdata   <= 32'd0;
            gpio_io_o          <= 32'd0;
            gpio_io_t          <= 32'd0;
        end else begin
            // Write Handshake (AMBA AXI4-Lite A3.3.1)
            if (!s_axi_miso.awready && s_axi_mosi.awvalid && s_axi_mosi.wvalid && !s_axi_miso.bvalid) begin
                s_axi_miso.awready <= 1'b1;
                s_axi_miso.wready  <= 1'b1;
                if (s_axi_mosi.awaddr[3:2] == 2'b00) begin
                    gpio_io_o <= s_axi_mosi.wdata;
                end else if (s_axi_mosi.awaddr[3:2] == 2'b01) begin
                    gpio_io_t <= s_axi_mosi.wdata;
                end
            end else if (s_axi_miso.awready && s_axi_mosi.awvalid && s_axi_miso.wready && s_axi_mosi.wvalid) begin
                s_axi_miso.awready <= 1'b0;
                s_axi_miso.wready  <= 1'b0;
                s_axi_miso.bvalid  <= 1'b1;
            end else begin
                s_axi_miso.awready <= 1'b0;
                s_axi_miso.wready  <= 1'b0;
                if (s_axi_miso.bvalid && s_axi_mosi.bready) begin
                    s_axi_miso.bvalid <= 1'b0;
                end
            end

            // Read Handshake (AMBA AXI4-Lite A3.3.1)
            if (!s_axi_miso.arready && s_axi_mosi.arvalid && !s_axi_miso.rvalid) begin
                s_axi_miso.arready <= 1'b1;
                if (s_axi_mosi.araddr[3:2] == 2'b00) begin
                    s_axi_miso.rdata <= (gpio_io_o & ~gpio_io_t) | (gpio_io_i & gpio_io_t);
                end else if (s_axi_mosi.araddr[3:2] == 2'b01) begin
                    s_axi_miso.rdata <= gpio_io_t;
                end else begin
                    s_axi_miso.rdata <= 32'd0;
                end
            end else if (s_axi_miso.arready && s_axi_mosi.arvalid) begin
                s_axi_miso.arready <= 1'b0;
                s_axi_miso.rvalid  <= 1'b1;
            end else begin
                s_axi_miso.arready <= 1'b0;
                if (s_axi_miso.rvalid && s_axi_mosi.rready) begin
                    s_axi_miso.rvalid <= 1'b0;
                end
            end
        end
    end

endmodule
`default_nettype wire
