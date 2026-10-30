// ============================================================================
// tb_serv_top_axi.sv
// Testbench Autonomo e Completo para o Core serv_top_axi
//
// Conecta o nucleo serv_top_axi (iBus e dBus) atraves do interconnect AXI4-Lite
// aos perifericos modulares necessarios e a BRAM:
//   - Slave 0: axi_lite_bram (Instrucoes e Dados)
//   - Slave 1: axi_lite_gpio (GPIO Dados: Valor de PI)
//   - Slave 2: axi_lite_gpio (GPIO LED / Status de Conclusao)
// ============================================================================
`timescale 1ns / 1ns
`default_nettype none

module tb_serv_top_axi;
    import axi_lite_pkg::*;

    parameter int ICACHE_WORDS = 64; // 0 = sem cache; >0 = tamanho da cache em palavras
    localparam int NUM_MASTERS = 2;  // iBus e dBus
    localparam int NUM_SLAVES  = 3;  // Slave 0: BRAM, Slave 1: GPIO_DATA, Slave 2: GPIO_LED

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
            32'h5000_0000, // Slave 2: GPIO LED / Status de Conclusao
            32'h4000_0000, // Slave 1: GPIO Dados (Valor de PI)
            32'h0000_0000  // Slave 0: BRAM (Instrucoes e Dados)
        }),
        .SLAVE_MASK  ({
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

    // Slave 1: Instancia Modular do Periferico AXI4-Lite GPIO (Dados / PI)
    logic [31:0] pi_val;
    axi_lite_gpio u_gpio_data (
        .s_axi_aclk    (clk),
        .s_axi_aresetn (rst_n),
        .s_axi_mosi    (s_axi_mosi[1]),
        .s_axi_miso    (s_axi_miso[1]),
        .gpio_io_i     (32'd0),
        .gpio_io_o     (pi_val),
        .gpio_io_t     ()
    );

    // Monitora escritas de progresso no GPIO de Dados
    logic [31:0] prev_pi_val;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_pi_val <= 32'd0;
        end else if (pi_val != 32'd0 && pi_val != prev_pi_val) begin
            prev_pi_val <= pi_val;
            $display("[%0t ns] >>> [GPIO PI PROGRESSO] Data = 0x%08x | Float = %f",
                     $time, pi_val, pi_val / (1.0 * (1 << 30)));
        end
    end

    // Slave 2: Instancia Modular do Periferico AXI4-Lite GPIO (LED / Conclusao)
    logic [31:0] gpio_led_val;
    logic        done_led;
    assign done_led = gpio_led_val[0];

    axi_lite_gpio u_gpio_led (
        .s_axi_aclk    (clk),
        .s_axi_aresetn (rst_n),
        .s_axi_mosi    (s_axi_mosi[2]),
        .s_axi_miso    (s_axi_miso[2]),
        .gpio_io_i     (32'd0),
        .gpio_io_o     (gpio_led_val),
        .gpio_io_t     ()
    );

    // Clock 50 MHz (periodo 20 ns)
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

    // Condicao de parada inteligente (disparada pelo LED)
    always_ff @(posedge clk) begin
        if (rst_n && done_led) begin
            #200;
            $display("=========================================================================");
            $display("[TB] SUCESSO: TESTBENCH serv_top_axi CONCLUIDO COM EXITO!");
            $display("     I-Cache Configuravel   : %0d palavras (%0d bytes)", ICACHE_WORDS, ICACHE_WORDS * 4);
            $display("     Resultado Final Q2.30  : 0x%08x", pi_val);
            $display("     Valor Convertido Float : %f", pi_val / (1.0 * (1 << 30)));
            $display("     Status LED / Conclusao : 1 (Escrita no Slave[2])");
            $display("=========================================================================");
            $finish;
        end
    end

    // Timeout de seguranca (2 ms)
    initial begin
        #2000000;
        $display("[TB] ERRO: Timeout atingido!");
        $finish;
    end

endmodule
`default_nettype wire
