// ============================================================================
// serv_icache.sv
// Cache de Instrucoes (I-Cache) de Mapeamento Direto para o Nucleo RISC-V SERV
//
// Caracteristicas:
//   - Conectada diretamente ao barramento de instrucao Wishbone do SERV (iBus)
//   - Zero sobrecarga de coherency/flush: codigo eh estritamente Read-Only
//   - Hit em 1 ciclo de clock: reduz >90% do trafego AXI em loops de instrucao
//   - Miss: repassa a requisicao ao arbitro AXI e grava o dado na linha de cache
//   - Parametrizavel via NUM_WORDS (ex: 64 palavras = 256 Bytes de cache)
// ============================================================================
`default_nettype none

module serv_icache #(
    parameter int NUM_WORDS = 64
) (
    input  logic        clk,
    input  logic        rst,

    // Interface com o Nucleo SERV (iBus Escravo)
    input  logic [31:0] cpu_adr,
    input  logic        cpu_cyc,
    output logic [31:0] cpu_rdt,
    output logic        cpu_ack,

    // Interface com o Arbitro AXI Master (iBus Mestre)
    output logic [31:0] mem_adr,
    output logic        mem_cyc,
    input  logic [31:0] mem_rdt,
    input  logic        mem_ack
);

    // Calculo sintetizavel de bits de indice
    function automatic int get_idx_bits(input int words);
        int b;
        int w;
        begin
            if (words <= 1) return 1;
            b = 0;
            w = words - 1;
            while (w > 0) begin
                b = b + 1;
                w = w >> 1;
            end
            return b;
        end
    endfunction

    localparam int IDX_BITS = get_idx_bits(NUM_WORDS);
    localparam int TAG_BITS = 32 - 2 - IDX_BITS;

    // Memoria interna da I-Cache: Tags, Valid e Dados (palavras de 32 bits)
    logic [TAG_BITS-1:0] tag_mem   [0:NUM_WORDS-1];
    logic                valid_mem [0:NUM_WORDS-1];
    logic [31:0]         data_mem  [0:NUM_WORDS-1];

    // Decomposicao do endereco RISC-V alinhado em palavras (bits [1:0] sempre 00)
    wire [IDX_BITS-1:0] line_idx = cpu_adr[IDX_BITS+1 : 2];
    wire [TAG_BITS-1:0] req_tag  = cpu_adr[31 : IDX_BITS+2];

    wire line_valid = valid_mem[line_idx];
    wire line_hit   = line_valid && (tag_mem[line_idx] == req_tag);

    // FSM de controle de Miss
    typedef enum logic {
        STATE_IDLE,
        STATE_MISS_WAIT
    } state_t;

    state_t state;

    always_ff @(posedge clk) begin
        if (rst) begin
            state   <= STATE_IDLE;
            cpu_ack <= 1'b0;
            cpu_rdt <= 32'd0;
            mem_cyc <= 1'b0;
            mem_adr <= 32'd0;
            for (int i = 0; i < NUM_WORDS; i++) begin
                valid_mem[i] <= 1'b0;
            end
        end else begin
            cpu_ack <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    if (cpu_cyc && !cpu_ack) begin
                        if (line_hit) begin
                            // Cache Hit: responde em 1 ciclo diretamente da memoria interna!
                            cpu_rdt <= data_mem[line_idx];
                            cpu_ack <= 1'b1;
                        end else begin
                            // Cache Miss: dispara leitura na BRAM via barramento AXI
                            mem_adr <= cpu_adr;
                            mem_cyc <= 1'b1;
                            state   <= STATE_MISS_WAIT;
                        end
                    end
                end

                STATE_MISS_WAIT: begin
                    if (mem_ack) begin
                        // Preenche a linha de cache com a nova instrucao
                        data_mem[line_idx]  <= mem_rdt;
                        tag_mem[line_idx]   <= req_tag;
                        valid_mem[line_idx] <= 1'b1;

                        // Responde a CPU e finaliza o ciclo AXI
                        cpu_rdt <= mem_rdt;
                        cpu_ack <= 1'b1;
                        mem_cyc <= 1'b0;
                        state   <= STATE_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
`default_nettype wire
