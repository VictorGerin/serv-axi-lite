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
├── sim/
│   ├── tb_serv_top_axi.sv   # Testbench autonomo com BRAM e Interconnect AXI4-Lite
│   ├── run_sim.sh           # Script de simulacao completo via sv2v + Icarus Verilog
│   └── firmware/
│       ├── main.c           # Firmware C de calculo de Pi (Leibniz) em ponto fixo Q2.30
│       ├── start.S          # Inicializacao baremetal RISC-V RV32I
│       ├── linker.ld        # Linker script baremetal (16 KB)
│       └── firmware.hex     # Binario pre-compilado pronto para simulacao
└── serv/                    # Submodulo git oficial do nucleo SERV (olofk/serv)
```

---

## 🧪 Simulação e Verificação

Você pode executar o fluxo completo (compilação do firmware via **Clang**, conversão SystemVerilog e simulação via **Icarus Verilog**) diretamente através do `Makefile`:

```bash
# 1. Verifica se todas as dependências estão presentes no ambiente
make check-deps

# 2. Compila o firmware C via Clang/LLVM e gera sim/firmware/firmware.hex
make firmware

# 3. Executa a simulação do testbench (tb_serv_top_axi) via Icarus Verilog
make sim

# Ou execute tudo de uma vez (firmware + sim):
make test
```

**Saída esperada no terminal:**
```text
=========================================================================
[TB] Iniciando Testbench Autonomo serv_top_axi (ICACHE_WORDS = 64)
=========================================================================
[TB] Reset desativado!
[399690 ns] >>> [GPIO PI PROGRESSO] Data = 0xffffffff | Float = 4.000000
[649050 ns] >>> [GPIO PI PROGRESSO] Data = 0xaaaaaaaa | Float = 2.666667
=========================================================================
[TB] SUCESSO: TESTBENCH serv_top_axi CONCLUIDO COM EXITO!
     I-Cache Configuravel   : 64 palavras (256 bytes)
     Resultado Final Q2.30  : 0xaaaaaaaa
     Valor Convertido Float : 2.666667
     Status LED / Conclusao : 1 (Escrita no Slave[3])
=========================================================================
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

## 💻 Compilação do Firmware (Clang / GCC)

O código fonte C utilizado no testbench está localizado em [`sim/firmware/`](file:///sim/firmware/) e calcula aproximações da série de Leibniz para $\pi$ em ponto fixo Q2.30 (`main.c`), com inicialização baremetal em assembly RV32I (`start.S`).

O arquivo [`sim/firmware/firmware.hex`](file:///sim/firmware/firmware.hex) incluído no repositório foi gerado a partir desse código fonte. Você pode recompilar o firmware facilmente usando o script automatizado ou diretamente via linha de comando com **Clang/LLVM** ou **GCC**.

### 1. Recompilação Automática (Script)

O script detecta automaticamente se você possui **Clang/LLVM** ou a toolchain **RISC-V GCC**:

```bash
cd sim/firmware
bash build_hex.sh
```

### 2. Compilação Manual com Clang / LLVM

O Clang possui suporte nativo à arquitetura RISC-V RV32I baremetal sem requerer uma toolchain externa separada:

```bash
cd sim/firmware

# Compila e linka diretamente para ELF RV32I baremetal
clang --target=riscv32 -march=rv32i -mabi=ilp32 -O2 -nostdlib \
      -Wl,-T,linker.ld start.S main.c -o pi.elf

# Gera o arquivo HEX no formato Verilog compatível com $readmemh (palavras de 32 bits)
llvm-objcopy -O verilog --verilog-data-width=4 pi.elf pi_raw.hex

# Ajusta formatação para o simulador
awk '!/^@/ { for(i=1; i<=NF; i++) print $i }' pi_raw.hex > firmware.hex
```

### 3. Compilação Manual com RISC-V GCC

Caso utilize a toolchain GNU (`riscv32-unknown-elf-gcc` ou `riscv64-unknown-elf-gcc`):

```bash
cd sim/firmware

# Compilação e linkedição com libgcc para suporte à divisão/multiplicação por software
riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 -O2 -nostartfiles \
      -T linker.ld start.S main.c -lgcc -Wl,--no-warn-mismatch -o pi.elf

# Extração do formato Verilog HEX
riscv32-unknown-elf-objcopy -O verilog --verilog-data-width=4 pi.elf pi_raw.hex

# Ajusta formatação para o simulador
awk '!/^@/ { for(i=1; i<=NF; i++) print $i }' pi_raw.hex > firmware.hex
```

---

## 📄 Licença

Distribuído sob a licença [Apache 2.0](LICENSE), compatível com o projeto SERV original.
