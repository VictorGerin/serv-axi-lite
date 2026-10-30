// ============================================================================
// Firmware Multi-Core em C para os Processadores RISC-V SERV (RV32I)
//
// Calculo Paralelo de PI em Ponto Fixo Q2.30 com Barreiras de Sincronizacao
// e Escritas Parciais no GPIO:
//     pi = 4 * (1 - 1/3 + 1/5 - 1/7 + 1/9 - ...)
//
// O processamento total eh dividido em RODADAS (ROUNDS):
//     - Em cada rodada, cada core calcula TERMS_PER_STEP termos locais.
//     - Ao final de cada rodada, todos os cores entram em uma Barreira de Sincronismo.
//     - O Core 0 acumula a reducao parcial e escreve no GPIO Dados (0x4000_0000).
//     - O Core 0 entao libera os demais cores para a proxima rodada!
//     - Ao terminar todas as rodadas, o Core 0 liga o LED (0x5000_0000).
// ============================================================================

typedef unsigned int uint32_t;
typedef int          int32_t;

// ----------------------------------------------------------------------------
// Mapa de Registradores do AXI4-Lite GPIO de Dados 32b (Slave[1] em 0x4000_0000)
// ----------------------------------------------------------------------------
#define AXI_GPIO_BASE       0x40000000UL
#define GPIO_DATA_REG       (*(volatile uint32_t *)(AXI_GPIO_BASE + 0x00))
#define GPIO_TRI_REG        (*(volatile uint32_t *)(AXI_GPIO_BASE + 0x04))

// ----------------------------------------------------------------------------
// Mapa de Registradores do AXI4-Lite GPIO de LED/Status (Slave[3] em 0x5000_0000)
// ----------------------------------------------------------------------------
#define AXI_LED_BASE        0x50000000UL
#define LED_DATA_REG        (*(volatile uint32_t *)(AXI_LED_BASE + 0x00))
#define LED_TRI_REG         (*(volatile uint32_t *)(AXI_LED_BASE + 0x04))

// ----------------------------------------------------------------------------
// Mapa de Registradores do AXI4-Lite SYSCON Multi-Core (Slave[2] em 0x8000_0000)
// ----------------------------------------------------------------------------
#define AXI_SYSCON_BASE     0x80000000UL
#define SYS_HART_ID         (*(volatile uint32_t *)(AXI_SYSCON_BASE + 0x00))
#define SYS_NUM_CORES       (*(volatile uint32_t *)(AXI_SYSCON_BASE + 0x04))
#define SYS_CORE_EN         (*(volatile uint32_t *)(AXI_SYSCON_BASE + 0x08))
#define SYS_CORE_SP(c)      (*(volatile uint32_t *)(AXI_SYSCON_BASE + 0x20 + ((c) * 8)))
#define SYS_CORE_PC(c)      (*(volatile uint32_t *)(AXI_SYSCON_BASE + 0x24 + ((c) * 8)))

// Maximo de cores suportados pelas pilhas pre-alocadas
#define MAX_CORES 8

// Pilhas dedicadas de 512 bytes (128 palavras) na RAM para cada Core (1..MAX_CORES-1)
uint32_t __attribute__((aligned(16))) core_stacks[MAX_CORES][128];

// Quantidade de termos que CADA core calcula por rodada antes de sincronizar
#define TERMS_PER_STEP 1

// Quantidade total de rodadas de processamento
#define TOTAL_ROUNDS   2

// Buffers compartilhados de sincronizacao e parcelas da rodada atual
volatile int32_t  pi_step_partial[MAX_CORES];
volatile uint32_t step_arrived[MAX_CORES];
volatile uint32_t step_round = 0;

// Divisao inteira unsigned de 2^32 por d (d = 2k + 1)
// Retorna (2^32 / d) em precisao de 32 bits (valor em Q2.30)
static inline uint32_t div_2pow32_by(uint32_t d) {
    uint32_t q = 0;
    uint32_t rem = 1; // Bit 32 do numerador (2^32)
    for (int i = 31; i >= 0; i--) {
        rem = (rem << 1);
        if (rem >= d) {
            rem -= d;
            q |= (1U << i);
        }
    }
    return q;
}

// Funcao de computacao paralela executada por cada Core
void compute_pi_worker(uint32_t core_id, uint32_t num_cores) {
    for (uint32_t r = 0; r < TOTAL_ROUNDS; r++) {
        int32_t local_step_sum = 0;

        // Cada core calcula TERMS_PER_STEP termos nesta rodada
        for (uint32_t t = 0; t < TERMS_PER_STEP; t++) {
            // Indice global do termo k na serie de Leibniz
            uint32_t k = (r * TERMS_PER_STEP * num_cores) + (t * num_cores) + core_id;
            uint32_t denom = (2 * k) + 1;
            uint32_t term = div_2pow32_by(denom);

            if ((k & 1) == 0) {
                local_step_sum += (int32_t)term;
            } else {
                local_step_sum -= (int32_t)term;
            }
        }

        // Publica o resultado desta rodada
        pi_step_partial[core_id] = local_step_sum;

        if (core_id == 0) {
            // O Core 0 aguarda todos os demais cores chegarem a barreira desta rodada
            for (uint32_t c = 1; c < num_cores && c < MAX_CORES; c++) {
                while (step_arrived[c] != (r + 1)) {
                    __asm__ volatile ("nop");
                }
            }

            // Core 0 soma as parcelas de todos os cores
            static int32_t running_pi = 0;
            for (uint32_t c = 0; c < num_cores && c < MAX_CORES; c++) {
                running_pi += pi_step_partial[c];
            }

            // ESCRITA NO GPIO DO RESULTADO PARCIAL DESTA RODADA!
            GPIO_DATA_REG = (uint32_t)running_pi;

            // Libera os outros cores incrementando o numero da rodada global
            step_round = r + 1;

        } else {
            // Core secundario sinaliza que chegou nesta rodada
            step_arrived[core_id] = r + 1;

            // Aguarda o Core 0 somar, escrever no GPIO e autorizar a proxima rodada
            while (step_round < (r + 1)) {
                __asm__ volatile ("nop");
            }
        }
    }
}

// Funcao de entrada para os Cores secundarios (Core 1, Core 2, ...)
void secondary_core_worker(uint32_t hart_id) {
    uint32_t num_cores = SYS_NUM_CORES;
    compute_pi_worker(hart_id, num_cores);

    while (1) {
        __asm__ volatile ("nop");
    }
}

// ============================================================================
// Funcao principal executada no Boot pelo Core 0 (Master Core)
// ============================================================================
int main(void) {
    // 1. Configura GPIOs como saida (Dados 32b e LED)
    GPIO_TRI_REG = 0x00000000;
    GPIO_DATA_REG = 0x00000000;

    LED_TRI_REG  = 0x00000000;
    LED_DATA_REG = 0x00000000; // LED comeca apagado (0)

    uint32_t num_cores = SYS_NUM_CORES;

    // Inicializa variaveis de barreira
    for (uint32_t c = 0; c < MAX_CORES; c++) {
        step_arrived[c] = 0;
        pi_step_partial[c] = 0;
    }
    step_round = 0;

    // 2. Configura Stack e Entry Point de TODOS os cores secundarios dinamicamente
    for (uint32_t c = 1; c < num_cores && c < MAX_CORES; c++) {
        SYS_CORE_SP(c) = (uint32_t)&core_stacks[c][128];
        SYS_CORE_PC(c) = (uint32_t)&secondary_core_worker;
    }

    // 3. Ativa todos os cores via mascara de bits
    uint32_t enable_mask = (num_cores >= 32) ? 0xFFFFFFFFU : ((1U << num_cores) - 1U);
    SYS_CORE_EN = enable_mask;

    // 4. Core 0 executa o worker com core_id = 0 e gerencia as sincronizacoes
    compute_pi_worker(0, num_cores);

    // 5. Ao finalizar TODAS as rodadas, ativa o LED físico (1) indicando conclusao!
    LED_DATA_REG = 0x00000001;

    // Loop final
    while (1) {
        __asm__ volatile ("nop");
    }

    return 0;
}
