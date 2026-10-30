// ============================================================================
// Firmware Single-Core em C para o Processador RISC-V SERV (RV32I)
//
// Calculo de PI em Ponto Fixo Q2.30 com Escritas no GPIO:
//     pi = 4 * (1 - 1/3 + 1/5 - 1/7 + 1/9 - ...)
//
// - A cada termo calculado, escreve o valor parcial no GPIO de Dados (0x4000_0000).
// - Ao concluir o calculo, escreve 1 no GPIO de LED / Conclusao (0x5000_0000).
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
// Mapa de Registradores do AXI4-Lite GPIO de LED/Status (Slave[2] em 0x5000_0000)
// ----------------------------------------------------------------------------
#define AXI_LED_BASE        0x50000000UL
#define LED_DATA_REG        (*(volatile uint32_t *)(AXI_LED_BASE + 0x00))
#define LED_TRI_REG         (*(volatile uint32_t *)(AXI_LED_BASE + 0x04))

// Quantidade de termos a calcular na serie de Leibniz
#define TOTAL_TERMS 2

// Divisao inteira unsigned de 2^32 por d (d = 2k + 1)
static inline uint32_t div_2_32_by_d(uint32_t d) {
    uint32_t rem = 0;
    uint32_t quo = 0;

    for (int i = 0; i < 32; i++) {
        rem = (rem << 1) | 1;
        quo = quo << 1;
        if (rem >= d) {
            rem -= d;
            quo |= 1;
        }
    }
    return quo;
}

int main(void) {
    // 1. Configura GPIOs como saida (Dados 32b e LED)
    GPIO_TRI_REG  = 0x00000000;
    GPIO_DATA_REG = 0x00000000;

    LED_TRI_REG   = 0x00000000;
    LED_DATA_REG  = 0x00000000; // Comeca em 0

    int32_t pi_accum = 0;

    // 2. Calcula termos da serie de Leibniz:
    //    Termo 0 (k=0): 4 * (1 / 1) = 4.0      (0xFFFFFFFF)
    //    Termo 1 (k=1): 4 * (-1 / 3) = -1.333333 -> Acumulado = 2.666667 (0xAAAAAAAA)
    for (uint32_t k = 0; k < TOTAL_TERMS; k++) {
        uint32_t d = (2 * k) + 1;
        uint32_t term_q32 = div_2_32_by_d(d);
        int32_t  term_q30 = (int32_t)(term_q32 >> 2);

        if ((k & 1) == 0) {
            pi_accum += term_q30;
        } else {
            pi_accum -= term_q30;
        }

        // Escreve resultado parcial no GPIO de Dados
        uint32_t pi_scaled = (uint32_t)pi_accum * 4;
        GPIO_DATA_REG = pi_scaled;
    }

    // 3. Ao finalizar, sinaliza conclusao escrevendo 1 no LED
    LED_DATA_REG = 0x00000001;

    while (1) {
        __asm__ volatile ("nop");
    }

    return 0;
}
