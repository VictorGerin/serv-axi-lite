// ============================================================================
// start.S
// Bootloader Multi-Core RISC-V (RV32I) integrado ao AXI4-Lite SYSCON:
//   - No Reset, apenas o Core 0 esta ativo (`CORE_EN = 1`).
//   - Quando qualquer Core sai do reset, ele le `SYS_HART_ID` em 0x8000_0000:
//       * Se `hart_id == 0`: inicializa `sp = 0x4000` (topo da BRAM de 16 KB)
//         e salta para `main()`, onde o Core 0 pode configurar a Stack e a
//         funcao de entrada dos outros Cores e ativa-los via `SYS_CORE_EN`.
//       * Se `hart_id > 0` : calcula o offset `0x8000_0020 + 8 * hart_id`,
//         carrega o seu `sp` de `SYS_CORE_SP[hart_id]` e salta para a funcao C
//         configurada pelo Core 0 em `SYS_CORE_PC[hart_id]`.
// ============================================================================
    .section .text.init
    .globl _start
_start:
    /* t0 = Endereco base do AXI4-Lite SYSCON (0x8000_0000) */
    lui     t0, 0x80000

    /* a0 = SYS_HART_ID (0x8000_0000) -> ID do Core atual (0, 1, ...) */
    lw      a0, 0(t0)

    /* Se for um Core secundario (a0 != 0), vai para o boot secundario */
    bnez    a0, _secondary_boot

    /* Boot do Core 0 (Master): sp = 0x0000_4000 e chama main() */
    lui     sp, 0x4
    jal     ra, main
    j       _hang

_secondary_boot:
    /* Endereco de configuracao do Core `a0`: t1 = 0x8000_0000 + (a0 << 3) */
    slli    t1, a0, 3
    add     t1, t0, t1

    /* Carrega o Stack Pointer configurado pelo Core 0 em CORE_SP[a0] (offset 0x20) */
    lw      sp, 32(t1)

    /* Carrega o Entry Point configurado pelo Core 0 em CORE_PC[a0] (offset 0x24) */
    lw      t2, 36(t1)

    /* Salta para a funcao C do Core secundario passando `a0 = hart_id` */
    jalr    ra, t2, 0

_hang:
    j       _hang
