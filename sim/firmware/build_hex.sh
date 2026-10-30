#!/bin/bash
set -e

if [ ! -d "/tmp/rv_gcc" ]; then
    mkdir -p /tmp/rv_gcc
    tar -xjf /tools_tar/riscv_toolchain.tar.bz2 -C /tmp/rv_gcc
fi
RV_BIN_DIR=$(dirname $(find /tmp/rv_gcc -name "*-gcc" | head -n 1))
RV_LIB_DIR=$(dirname "$RV_BIN_DIR")/lib
export PATH="$RV_BIN_DIR:$PATH"
export LD_LIBRARY_PATH="$RV_LIB_DIR:$LD_LIBRARY_PATH"
RV_PREFIX=$(basename $(find "$RV_BIN_DIR" -name "*-gcc" | head -n 1) -gcc)

cd /work/sim/firmware
${RV_PREFIX}-gcc -march=rv32i -mabi=ilp32 -O2 -nostartfiles -T linker.ld -o pi.elf start.S main.c -lgcc -Wl,--no-warn-mismatch
${RV_PREFIX}-objcopy -O verilog --verilog-data-width=4 pi.elf pi_raw.hex
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
echo "firmware.hex gerado com sucesso!"
