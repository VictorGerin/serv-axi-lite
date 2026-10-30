#!/bin/bash
# ==============================================================================
# build_hex.sh - Compilacao do Firmware Baremetal RISC-V RV32I para HEX
#
# Suporta compilacao tanto via GCC (riscv32-unknown-elf-gcc) quanto via Clang/LLVM:
#
# Exemplo com Clang:
#   clang --target=riscv32 -march=rv32i -mabi=ilp32 -O2 -nostdlib \
#         -Wl,-T,linker.ld start.S main.c -o pi.elf
#   llvm-objcopy -O verilog --verilog-data-width=4 pi.elf pi_raw.hex
#
# Exemplo com GCC:
#   riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 -O2 -nostartfiles \
#         -T linker.ld start.S main.c -lgcc -Wl,--no-warn-mismatch -o pi.elf
#   riscv32-unknown-elf-objcopy -O verilog --verilog-data-width=4 pi.elf pi_raw.hex
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Detecta Clang ou GCC disponivel no ambiente
if command -v clang >/dev/null 2>&1; then
    CC="clang --target=riscv32 -march=rv32i -mabi=ilp32"
    OBJCOPY="llvm-objcopy"
    LDFLAGS="-nostdlib -Wl,-T,linker.ld"
elif command -v riscv32-unknown-elf-gcc >/dev/null 2>&1; then
    CC="riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32"
    OBJCOPY="riscv32-unknown-elf-objcopy"
    LDFLAGS="-nostartfiles -T linker.ld -lgcc -Wl,--no-warn-mismatch"
else
    # Fallback procurando GCC no toolchain local /tmp/rv_gcc
    RV_BIN_DIR=$(dirname $(find /tmp/rv_gcc -name "*-gcc" 2>/dev/null | head -n 1) 2>/dev/null || true)
    if [ -n "$RV_BIN_DIR" ] && [ -d "$RV_BIN_DIR" ]; then
        RV_PREFIX=$(basename $(find "$RV_BIN_DIR" -name "*-gcc" | head -n 1) -gcc)
        export PATH="$RV_BIN_DIR:$PATH"
        export LD_LIBRARY_PATH="$(dirname "$RV_BIN_DIR")/lib:$LD_LIBRARY_PATH"
        CC="${RV_PREFIX}-gcc -march=rv32i -mabi=ilp32"
        OBJCOPY="${RV_PREFIX}-objcopy"
        LDFLAGS="-nostartfiles -T linker.ld -lgcc -Wl,--no-warn-mismatch"
    else
        echo "ERRO: Nao foi encontrado compilador Clang nem GCC RISC-V no PATH."
        exit 1
    fi
fi

echo ">>> Compilando firmware via $CC..."
$CC -O2 $LDFLAGS start.S main.c -o pi.elf
$OBJCOPY -O verilog --verilog-data-width=4 pi.elf pi_raw.hex

echo ">>> Formatando para firmware.hex (16 KB / 4096 palavras alinhadas)..."
python3 - << 'EOF'
with open("pi_raw.hex", "r") as fin, open("firmware.hex", "w") as fout:
    mem = [0] * 4096 # 16 KB = 4096 palavras de 32 bits
    addr = 0
    for line in fin:
        line = line.strip()
        if not line:
            continue
        if line.startswith("@"):
            addr = int(line[1:], 16)
        else:
            for tok in line.split():
                if addr < 4096:
                    mem[addr] = int(tok, 16)
                addr += 1
    for val in mem:
        fout.write(f"{val:08x}\n")
EOF

rm -f pi.elf pi_raw.hex
echo ">>> Sucesso: sim/firmware/firmware.hex atualizado!"
