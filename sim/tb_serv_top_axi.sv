// ============================================================================
// tb_serv_top_axi.sv
// Testbench Autonomo e Completo para o Core serv_top_axi
//
// Conecta o nucleo serv_top_axi (iBus e dBus) atraves do interconnect AXI4-Lite
// aos perifericos e a BRAM, executando o firmware de calculo de PI (Leibniz)
// ============================================================================
`timescale 1ns / 1ns
`default_nettype none

module tb_serv_top_axi;
    import axi_lite_pkg::*;

    parameter int ICACHE_WORDS = 64; // 0 = sem cache; >0 = tamanho da cache em palavras
    localparam int NUM_MASTERS = 2;  // iBus e dBus
    localparam int NUM_SLAVES  = 4;  // BRAM, GPIO_DATA, SYSCON, GPIO_LED

    logic clk;
    logic rst_n;

    // Barramentos AXI4-Lite Masters (do nucleo para o interconnect)
    axi_lite_mosi_t [NUM_MASTERS-1:0] m_axi_mosi;
    axi_lite_miso_t [NUM_MASTERS-1:0] m_axi_miso;

    // Barramentos AXI4-Lite Slaves (do interconnect para os perifericos)
    axi_lite_mosi_t [NUM_SLAVES-1:0]  s_axi_mosi;
    axi_lite_miso_t [NUM_SLAVES-1:0]  s_axi_miso;

    // Instancia do Nucleo sob Teste (DUT)
    serv_top_axi #(
        .RESET_PC     (32'h0000_0000),
        .ICACHE_WORDS (ICACHE_WORDS)
    ) dut (
        .aclk            (clk),
        .aresetn         (rst_n),
        .i_timer_irq     (1'b0),
        .m_axi_ibus_mosi (m_axi_mosi[0]),
        .m_axi_ibus_miso (m_axi_miso[0]),
        .m_axi_dbus_mosi (m_axi_mosi[1]),
        .m_axi_dbus_miso (m_axi_miso[1])
    );

    // Interconnect AXI4-Lite Multi-Master / Multi-Slave
    axi_lite_interconnect #(
        .NUM_MASTERS (NUM_MASTERS),
        .NUM_SLAVES  (NUM_SLAVES),
        .SLAVE_BASE  ({
            32'h5000_0000, // Slave 3: GPIO LED / Status de Conclusao
            32'h8000_0000, // Slave 2: SYSCON
            32'h4000_0000, // Slave 1: GPIO Dados (Valor de PI)
            32'h0000_0000  // Slave 0: BRAM (Instrucoes e Dados)
        }),
        .SLAVE_MASK  ({
            32'hF000_0000,
            32'hF000_0000,
            32'hF000_0000,
            32'hF000_0000
        })
    ) u_interconnect (
        .aclk       (clk),
        .aresetn    (rst_n),
        .m_axi_mosi (m_axi_mosi),
        .m_axi_miso (m_axi_miso),
        .s_axi_mosi (s_axi_mosi),
        .s_axi_miso (s_axi_miso)
    );

    // Slave 0: BRAM Unificada de 16 KB (carrega firmware.hex)
    axi_lite_bram u_bram (
        .s_axi_aclk    (clk),
        .s_axi_aresetn (rst_n),
        .s_axi_mosi    (s_axi_mosi[0]),
        .s_axi_miso    (s_axi_miso[0])
    );

    // Slave 1: GPIO de Dados (captura o valor de PI)
    logic [31:0] pi_val;
    assign s_axi_miso[1].bresp   = 2'b00;
    assign s_axi_miso[1].rresp   = 2'b00;
    assign s_axi_miso[1].rdata   = pi_val;
    assign s_axi_miso[1].arready = 1'b1;
    assign s_axi_miso[1].rvalid  = s_axi_mosi[1].arvalid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_miso[1].awready <= 1'b0;
            s_axi_miso[1].wready  <= 1'b0;
            s_axi_miso[1].bvalid  <= 1'b0;
            pi_val                <= 32'd0;
        end else begin
            if (!s_axi_miso[1].awready && s_axi_mosi[1].awvalid && s_axi_mosi[1].wvalid && !s_axi_miso[1].bvalid) begin
                s_axi_miso[1].awready <= 1'b1;
                s_axi_miso[1].wready  <= 1'b1;
            end else if (s_axi_miso[1].awready && s_axi_miso[1].wready) begin
                s_axi_miso[1].awready <= 1'b0;
                s_axi_miso[1].wready  <= 1'b0;
                s_axi_miso[1].bvalid  <= 1'b1;
                if (s_axi_mosi[1].awaddr[3:2] == 2'b00 && s_axi_mosi[1].wdata != 32'd0) begin
                    pi_val <= s_axi_mosi[1].wdata;
                    $display("[%0t ns] >>> [GPIO PI PROGRESSO] Data = 0x%08x | Float = %f",
                             $time, s_axi_mosi[1].wdata, s_axi_mosi[1].wdata / (1.0 * (1 << 30)));
                end
            end else if (s_axi_miso[1].bvalid && s_axi_mosi[1].bready) begin
                s_axi_miso[1].bvalid <= 1'b0;
            end
        end
    end

    // Slave 2: SYSCON Simples (HART_ID = 0, NUM_CORES = 1)
    assign s_axi_miso[2].bresp   = 2'b00;
    assign s_axi_miso[2].rresp   = 2'b00;
    assign s_axi_miso[2].arready = 1'b1;
    assign s_axi_miso[2].rvalid  = s_axi_mosi[2].arvalid;

    always_comb begin
        if (s_axi_mosi[2].araddr[5:2] == 4'h0)
            s_axi_miso[2].rdata = 32'd0; // HART_ID = 0
        else if (s_axi_mosi[2].araddr[5:2] == 4'h1)
            s_axi_miso[2].rdata = 32'd1; // NUM_CORES = 1
        else
            s_axi_miso[2].rdata = 32'd1; // CORE_EN = 1
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_miso[2].awready <= 1'b0;
            s_axi_miso[2].wready  <= 1'b0;
            s_axi_miso[2].bvalid  <= 1'b0;
        end else begin
            if (!s_axi_miso[2].awready && s_axi_mosi[2].awvalid && s_axi_mosi[2].wvalid && !s_axi_miso[2].bvalid) begin
                s_axi_miso[2].awready <= 1'b1;
                s_axi_miso[2].wready  <= 1'b1;
            end else if (s_axi_miso[2].awready && s_axi_miso[2].wready) begin
                s_axi_miso[2].awready <= 1'b0;
                s_axi_miso[2].wready  <= 1'b0;
                s_axi_miso[2].bvalid  <= 1'b1;
            end else if (s_axi_miso[2].bvalid && s_axi_mosi[2].bready) begin
                s_axi_miso[2].bvalid <= 1'b0;
            end
        end
    end

    // Slave 3: GPIO LED / Conclusao
    logic done_led;
    assign s_axi_miso[3].bresp   = 2'b00;
    assign s_axi_miso[3].rresp   = 2'b00;
    assign s_axi_miso[3].rdata   = {31'd0, done_led};
    assign s_axi_miso[3].arready = 1'b1;
    assign s_axi_miso[3].rvalid  = s_axi_mosi[3].arvalid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_miso[3].awready <= 1'b0;
            s_axi_miso[3].wready  <= 1'b0;
            s_axi_miso[3].bvalid  <= 1'b0;
            done_led              <= 1'b0;
        end else begin
            if (!s_axi_miso[3].awready && s_axi_mosi[3].awvalid && s_axi_mosi[3].wvalid && !s_axi_miso[3].bvalid) begin
                s_axi_miso[3].awready <= 1'b1;
                s_axi_miso[3].wready  <= 1'b1;
            end else if (s_axi_miso[3].awready && s_axi_miso[3].wready) begin
                s_axi_miso[3].awready <= 1'b0;
                s_axi_miso[3].wready  <= 1'b0;
                s_axi_miso[3].bvalid  <= 1'b1;
                if (s_axi_mosi[3].wdata[0]) done_led <= 1'b1;
            end else if (s_axi_miso[3].bvalid && s_axi_mosi[3].bready) begin
                s_axi_miso[3].bvalid <= 1'b0;
            end
        end
    end

    // Clock 50 MHz
    always #10 clk = ~clk;

    // Inicializacao
    initial begin
        clk   = 0;
        rst_n = 0;
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_serv_top_axi);
        $display("=========================================================================");
        $display("[TB] Iniciando Testbench Autonomo serv_top_axi (ICACHE_WORDS = %0d)", ICACHE_WORDS);
        $display("=========================================================================");
        #100;
        rst_n = 1;
        $display("[TB] Reset desativado!");
    end

    // Condicao de parada inteligente
    always_ff @(posedge clk) begin
        if (rst_n && done_led) begin
            #200;
            $display("=========================================================================");
            $display("[TB] SUCESSO: TESTBENCH serv_top_axi CONCLUIDO COM EXITO!");
            $display("     I-Cache Configuravel   : %0d palavras (%0d bytes)", ICACHE_WORDS, ICACHE_WORDS * 4);
            $display("     Resultado Final Q2.30  : 0x%08x", pi_val);
            $display("     Valor Convertido Float : %f", pi_val / (1.0 * (1 << 30)));
            $display("     Status LED / Conclusao : 1 (Escrita no Slave[3])");
            $display("=========================================================================");
            $finish;
        end
    end

    // Timeout (2 ms)
    initial begin
        #2000000;
        $display("[TB] ERRO: Timeout atingido!");
        $finish;
    end

endmodule
`default_nettype wire
