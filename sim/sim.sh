#!/usr/bin/env bash
# ==============================================================================
# sim/sim.sh - Execucao de simulacao autonoma do serv-axi-lite
#
# Detecta se sv2v esta instalado no host local (ex: Linux nativo).
# Caso nao esteja, utiliza o container Docker serv-axi-ise com sv2v + iverilog.
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ICACHE="${1:-64}"

if command -v sv2v >/dev/null 2>&1 && command -v iverilog >/dev/null 2>&1; then
    echo ">>> Executando simulacao localmente no host (sv2v + iverilog)..."
    bash "${SCRIPT_DIR}/run_sim.sh" "$ICACHE"
else
    echo ">>> sv2v nao encontrado no host. Executando simulacao via Docker (serv-axi-ise)..."
    if command -v cygpath >/dev/null 2>&1; then
        WORK_MOUNT="$(cygpath -m "$REPO_ROOT")"
    else
        WORK_MOUNT="$REPO_ROOT"
    fi

    docker run --rm \
        -v "${WORK_MOUNT}:/work" \
        serv-axi-ise:latest \
        -c "bash /work/sim/run_sim.sh $ICACHE"
fi
