# serv-axi-lite

> **RISC-V SERV Core encapsulado com interfaces ARM AXI4-Lite duplas (iBus e dBus independentes) e Cache de Instruções (I-Cache) configurável.**

Este repositório transforma o premiado **[SERV (SErial RISC-V)](https://github.com/olofk/serv)** de Olof Kindgren — o menor núcleo de processador RISC-V do mundo — em um bloco IP pronto para uso em barramentos industriais **ARM AMBA AXI4-Lite**.

---

## 🚀 Destaques da Arquitetura

1. **Dual AXI4-Lite Masters**:
   - `m_axi_ibus`: Canal AXI Master dedicado à busca de instruções (*Fetch*).
   - `m_axi_dbus`: Canal AXI Master dedicado a leituras e escritas de dados (*Load/Store* com suporte total a `WSTRB`).
   - Elimina contenções internas de arbitragem dentro do núcleo: a arbitragem fica a cargo do Interconnect do SoC.

2. **Ponte Desacoplada `wb_to_axi_lite`**:
   - Converte Wishbone B3 Classic para ARM AXI4-Lite Master.
   - Handshakes assíncronos e independentes nos canais `AW`, `W`, `B`, `AR` e `R`.
   - **Verificado Formalmente** com os checkers ARM `Axi4LitePC` com **zero violações**.

3. **I-Cache de Instruções Opcional (`serv_icache`)**:
   - Parâmetro `ICACHE_WORDS`: define o número de palavras da cache de mapeamento direto (ex: `64` = 256 bytes).
   - Se `ICACHE_WORDS = 0`: **100% bypass direto** sem latência nem LUTs adicionais.
   - Hit em **1 ciclo de clock**, aliviando o tráfego no barramento e acelerando loops em até dezenas de vezes.

4. **RF (Register File) Eficiente**:
   - Implementado internamente com organização de 512 x 2 bits, mapeando diretamente para memórias distribuídas (LUT RAM) ou Block RAMs em FPGAs Xilinx/Intel.

---

## 📂 Estrutura do Repositório

```
serv-axi-lite/
├── rtl/
│   ├── axi_lite_pkg.sv      # Structs de barramento SystemVerilog (axi_lite_mosi_t, axi_lite_miso_t)
│   ├── serv_top_axi.sv      # Modulo topo do processador SERV com interfaces AXI4-Lite
│   ├── wb_to_axi_lite.sv    # Ponte de conversao Wishbone B3 -> AXI4-Lite Master
│   └── serv_icache.sv       # Cache de instrucoes de mapeamento direto configuravel
└── serv/                    # Submodulo git oficial do nucleo SERV (olofk/serv)
```

---

## 🛠️ Como Usar (Exemplo SystemVerilog)

```systemverilog
import axi_lite_pkg::*;

serv_top_axi #(
    .RESET_PC     (32'h0000_0000), // Endereco inicial de boot
    .ICACHE_WORDS (64)             // 64 palavras (256 bytes) de I-Cache (0 = desativada)
) u_cpu (
    .aclk            (clk),
    .aresetn         (rst_n),
    .i_timer_irq     (1'b0),
    
    // Interface Mestre de Instrucao (Fetch)
    .m_axi_ibus_mosi (cpu_ibus_mosi),
    .m_axi_ibus_miso (cpu_ibus_miso),
    
    // Interface Mestre de Dados (Load / Store)
    .m_axi_dbus_mosi (cpu_dbus_mosi),
    .m_axi_dbus_miso (cpu_dbus_miso)
);
```

---

## 📄 Licença

Distribuído sob a licença [Apache 2.0](LICENSE), compatível com o projeto SERV original.
