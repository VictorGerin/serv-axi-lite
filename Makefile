# ==============================================================================
# Makefile - serv-axi-lite (RISC-V SERV + AXI4-Lite IP Core)
# ==============================================================================
# Targets principais:
#   make check-deps  - Verifica disponibilidade de Clang, LLVM, Icarus e Docker/sv2v
#   make firmware    - Compila o firmware C (Leibniz Pi) com Clang e gera firmware.hex
#   make sim         - Executa o testbench do processador via Icarus Verilog
#   make test        - Executa o ciclo completo (firmware + sim)
#   make clean       - Remove arquivos temporários de compilação e simulação
# ==============================================================================

SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c

# Seleção de compiladores e ferramentas
# Procura explicitamente pelo Clang/LLVM do MSYS2 clang64 (que possui suporte ao target riscv32)
CLANG_CANDIDATE := $(shell if [ -x /c/msys64/clang64/bin/clang ]; then echo /c/msys64/clang64/bin/clang; \
                           elif [ -x /c/msys64/clang64/bin/clang.exe ]; then echo /c/msys64/clang64/bin/clang.exe; \
                           elif [ -f C:/msys64/clang64/bin/clang.exe ]; then echo C:/msys64/clang64/bin/clang.exe; \
                           else which clang 2>/dev/null || echo clang; fi)

OBJCOPY_CANDIDATE := $(shell if [ -x /c/msys64/clang64/bin/llvm-objcopy ]; then echo /c/msys64/clang64/bin/llvm-objcopy; \
                             elif [ -x /c/msys64/clang64/bin/llvm-objcopy.exe ]; then echo /c/msys64/clang64/bin/llvm-objcopy.exe; \
                             elif [ -f C:/msys64/clang64/bin/llvm-objcopy.exe ]; then echo C:/msys64/clang64/bin/llvm-objcopy.exe; \
                             else which llvm-objcopy 2>/dev/null || echo llvm-objcopy; fi)

CLANG_BIN ?= $(CLANG_CANDIDATE)
OBJCOPY_BIN ?= $(OBJCOPY_CANDIDATE)
PYTHON_BIN ?= $(shell which python 2>/dev/null || which python3 2>/dev/null || echo python)

IVERILOG_BIN ?= $(shell which iverilog 2>/dev/null || echo iverilog)
VVP_BIN ?= $(shell which vvp 2>/dev/null || echo vvp)
SV2V_BIN ?= $(shell which sv2v 2>/dev/null || echo sv2v)
DOCKER_BIN ?= $(shell which docker 2>/dev/null || echo docker)

FW_DIR := sim/firmware
FW_SRC := $(FW_DIR)/main.c $(FW_DIR)/start.S
FW_LDS := $(FW_DIR)/linker.ld
FW_ELF := $(FW_DIR)/pi.elf
FW_BIN := $(FW_DIR)/pi.bin
FW_HEX := $(FW_DIR)/firmware.hex
BIN2HEX := $(FW_DIR)/bin2hex.py

.PHONY: all help check-deps firmware sim test clean

all: test

help:
	@echo "=============================================================================="
	@echo "                      serv-axi-lite Build & Testbench System                  "
	@echo "=============================================================================="
	@echo "  make check-deps  : Verifica ferramentas instaladas (Clang, LLVM, Icarus, etc)"
	@echo "  make firmware    : Compila main.c via Clang/LLVM e gera firmware.hex"
	@echo "  make sim         : Executa a simulacao RTL do SERV AXI-Lite com Icarus Verilog"
	@echo "  make test        : Executa build do firmware seguido da simulacao completa"
	@echo "  make clean       : Limpa binarios, dumps VCD e diretorios de build"
	@echo "=============================================================================="

## -----------------------------------------------------------------------------
## 1. Verificação de Dependências
## -----------------------------------------------------------------------------
check-deps:
	@echo "=============================================================================="
	@echo ">>> Verificando dependencias de software..."
	@echo "=============================================================================="
	@MISSING=0; \
	check_tool() { \
		local name="$$1"; \
		local cmd="$$2"; \
		local desc="$$3"; \
		printf "  %-16s : " "$$name"; \
		if command -v "$$cmd" >/dev/null 2>&1 || [ -f "$$cmd" ]; then \
			echo "[OK] ($$cmd)"; \
		else \
			echo "[FALTA] - $$desc"; \
			MISSING=$$((MISSING + 1)); \
		fi \
	}; \
	check_tool "clang" "$(CLANG_BIN)" "Compilador C para baremetal RV32I"; \
	check_tool "llvm-objcopy" "$(OBJCOPY_BIN)" "Extrator de binario LLVM"; \
	check_tool "python3/python" "$(PYTHON_BIN)" "Conversor de binario para HEX Verilog"; \
	check_tool "iverilog" "$(IVERILOG_BIN)" "Simulador Icarus Verilog"; \
	check_tool "vvp" "$(VVP_BIN)" "Engine de runtime Icarus Verilog"; \
	if command -v sv2v >/dev/null 2>&1; then \
		printf "  %-16s : [OK] (sv2v nativo disponivel)\n" "sv2v"; \
	elif command -v docker >/dev/null 2>&1; then \
		printf "  %-16s : [OK] (via Docker serv-axi-ise container)\n" "sv2v/docker"; \
	else \
		printf "  %-16s : [FALTA] - Necessario sv2v ou docker para converter SystemVerilog\n" "sv2v/docker"; \
		MISSING=$$((MISSING + 1)); \
	fi; \
	echo "------------------------------------------------------------------------------"; \
	if [ $$MISSING -eq 0 ]; then \
		echo ">>> Todas as dependencias estao satisfeitas com sucesso!"; \
	else \
		echo ">>> AVISO: $$MISSING ferramenta(s) faltando. Verifique as instrucoes acima."; \
	fi; \
	echo "=============================================================================="

## -----------------------------------------------------------------------------
## 2. Build do Firmware com Clang / LLVM
## -----------------------------------------------------------------------------
firmware: $(FW_HEX)

$(FW_HEX): $(FW_SRC) $(FW_LDS) $(BIN2HEX)
	@echo ">>> [1/3] Compilando firmware RISC-V RV32I com Clang..."
	@$(CLANG_BIN) -fuse-ld=lld \
		--target=riscv32 \
		-march=rv32i \
		-mabi=ilp32 \
		-O2 \
		-nostdlib \
		-Wl,-T,$(FW_LDS) \
		$(FW_SRC) \
		-o $(FW_ELF)
	@echo ">>> [2/3] Extraindo binario bruto via llvm-objcopy..."
	@$(OBJCOPY_BIN) -O binary $(FW_ELF) $(FW_BIN)
	@echo ">>> [3/3] Formatando para firmware.hex (16 KB / 4096 palavras)..."
	@$(PYTHON_BIN) $(BIN2HEX) $(FW_BIN) $(FW_HEX)
	@rm -f $(FW_ELF) $(FW_BIN)

## -----------------------------------------------------------------------------
## 3. Simulação com Icarus Verilog (TB serv_top_axi)
## -----------------------------------------------------------------------------
sim: $(FW_HEX)
	@echo ">>> Executando simulacao do Testbench..."
	@bash sim/sim.sh

test: firmware sim

## -----------------------------------------------------------------------------
## 4. Limpeza
## -----------------------------------------------------------------------------
clean:
	@echo ">>> Limpando arquivos temporarios e de simulacao..."
	@rm -rf build/
	@rm -f $(FW_ELF) $(FW_BIN)
	@rm -f *.vvp *.vcd
	@echo ">>> Concluido!"
