#!/usr/bin/env bash
# ==============================================================================
# run_sim.sh - Converte SV para Verilog e executa via Icarus Verilog (iverilog/vvp)
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

mkdir -p "$ROOT_DIR/build/sim/rtl"
cd "$ROOT_DIR/build/sim"

cp "$ROOT_DIR/sim/firmware/firmware.hex" ./firmware.hex

echo ">>> [1/2] Convertendo SystemVerilog para Verilog via sv2v..."
sv2v \
    "$ROOT_DIR/rtl/axi_lite_pkg.sv" \
    "$ROOT_DIR/rtl/wb_to_axi_lite.sv" \
    "$ROOT_DIR/rtl/serv_icache.sv" \
    "$ROOT_DIR/rtl/serv_top_axi.sv" \
    "$ROOT_DIR/sim/axi_lite_interconnect.sv" \
    "$ROOT_DIR/sim/axi_lite_bram.sv" \
    "$ROOT_DIR/sim/tb_serv_top_axi.sv" \
    --write=./rtl

SERV_FILES=$(find "$ROOT_DIR/serv/rtl" -maxdepth 1 -type f -name "*.v" \
    ! -name "serv_rf_ram.v" \
    ! -name "serv_rf_ram_if.v" \
    ! -name "serv_rf_top.v" \
    ! -name "serv_synth_wrapper.v" | sort)

echo ">>> [2/2] Compilando e executando Icarus Verilog..."
iverilog -g2012 -o tb_serv_top_axi.vvp $SERV_FILES ./rtl/*.v
vvp tb_serv_top_axi.vvp
