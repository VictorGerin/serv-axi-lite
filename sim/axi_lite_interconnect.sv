// ============================================================================
// axi_lite_interconnect.sv
// Interconnect AXI4-Lite Multi-Master / Multi-Slave Parametrizavel e Otimizado
// (NUM_MASTERS Masters -> NUM_SLAVES Slaves)
//
// Conformidade AMBA AXI4-Lite:
//   - Arbitragem Round-Robin entre os NUM_MASTERS Masters (CPUs/Perifericos)
//   - Injeta automaticamente o indice do Master vencedor em `s_axi_mosi.master_id`
//   - Decodificacao de enderecos parametrizada via `SLAVE_BASE` e `SLAVE_MASK`
//     com travamento (latch) do Slave alvo durante toda a transacao
//   - Rastreamento independente dos handshakes AW, W, B, AR e R (suporta Slaves
//     que aceitam AW e W em ciclos distintos ou mantem READY pre-ativado)
//   - Default Slave integrado: responde automaticamente `DECERR` (2'b11) caso um
//     Master acesse um endereco nao mapeado em nenhum Slave, evitando deadlock
//
// Otimizacoes de Sintese FPGA (Spartan-6 / XST):
//   - Larguras de barramento de controle limitadas a $clog2(NUM_MASTERS) e $clog2(NUM_SLAVES)
//   - Eliminacao de indexacao dinamica variavel em structs compactadas (substituida
//     por decodificacao explícita via loops estaticos), reduzindo milhares de LUTs.
// ============================================================================
`default_nettype none

module axi_lite_interconnect
    import axi_lite_pkg::*;
#(
    parameter int NUM_MASTERS = 2,
    parameter int NUM_SLAVES  = 3,
    parameter logic [NUM_SLAVES-1:0][31:0] SLAVE_BASE = {
        32'h8000_0000, // Slave 2: SYSCON (Multi-Core Control)
        32'h4000_0000, // Slave 1: GPIO
        32'h0000_0000  // Slave 0: BRAM
    },
    parameter logic [NUM_SLAVES-1:0][31:0] SLAVE_MASK = {
        32'hF000_0000, // Slave 2: 0x8xxx_xxxx
        32'hF000_0000, // Slave 1: 0x4xxx_xxxx
        32'hF000_0000  // Slave 0: 0x0xxx_xxxx
    }
) (
    input  logic                              aclk,
    input  logic                              aresetn,

    // Array de Barramentos AXI4-Lite conectado aos M Masters (CPUs)
    input  axi_lite_mosi_t [NUM_MASTERS-1:0]  m_axi_mosi,
    output axi_lite_miso_t [NUM_MASTERS-1:0]  m_axi_miso,

    // Array de Barramentos AXI4-Lite conectado aos N Slaves (Memorias/Perifericos)
    output axi_lite_mosi_t [NUM_SLAVES-1:0]   s_axi_mosi,
    input  axi_lite_miso_t [NUM_SLAVES-1:0]   s_axi_miso
);

    function automatic int calc_width(input int val);
        int w;
        int v;
        begin
            if (val <= 1) return 1;
            w = 0;
            v = val - 1;
            while (v > 0) begin
                w = w + 1;
                v = v >> 1;
            end
            return w;
        end
    endfunction

    localparam int M_WIDTH = calc_width(NUM_MASTERS);
    localparam int S_WIDTH = calc_width(NUM_SLAVES);

    // ------------------------------------------------------------------------
    // 1. Arbitro Round-Robin Multi-Master (NUM_MASTERS -> 1 Active Transaction)
    // ------------------------------------------------------------------------
    logic [NUM_MASTERS-1:0] m_req;
    logic [NUM_MASTERS-1:0] m_active;
    logic [M_WIDTH-1:0]     grant_id;
    logic [M_WIDTH-1:0]     rr_ptr;
    logic                   bus_busy;
    logic                   is_write;
    logic [S_WIDTH-1:0]     target_slave;
    logic                   decode_err;

    // Rastreamento independente de handshakes por canal AXI4-Lite
    logic                   aw_done;
    logic                   w_done;
    logic                   ar_done;
    logic                   decerr_bvalid;
    logic                   decerr_rvalid;

    always_comb begin
        for (int m = 0; m < NUM_MASTERS; m++) begin
            // Nova transacao inicia quando Master apresenta endereco de Escrita (AW) ou Leitura (AR)
            m_req[m]    = m_axi_mosi[m].awvalid | m_axi_mosi[m].arvalid;
            // Mantem transacao viva enquanto houver canais pendentes (ou ate reset do Master)
            m_active[m] = m_axi_mosi[m].awvalid | m_axi_mosi[m].wvalid | m_axi_mosi[m].bready |
                          m_axi_mosi[m].arvalid | m_axi_mosi[m].rready;
        end
    end

    // Seleciona o proximo Master em Round-Robin a partir de `rr_ptr`
    logic [M_WIDTH-1:0]  next_grant_id;
    logic                found_req;
    logic                next_is_write;
    logic [31:0]         next_req_addr;
    logic [S_WIDTH-1:0]  next_target_slave;
    logic                next_decode_err;

    always_comb begin
        next_grant_id = grant_id;
        found_req     = 1'b0;
        for (int offset = 0; offset < NUM_MASTERS; offset++) begin
            int idx;
            idx = offset + int'(rr_ptr);
            if (idx >= NUM_MASTERS)
                idx = idx - NUM_MASTERS;
            if (!found_req && m_req[idx]) begin
                next_grant_id = idx[M_WIDTH-1:0];
                found_req     = 1'b1;
            end
        end

        // Selecao estatica do endereco do master vencedor para decodificacao
        next_is_write = 1'b0;
        next_req_addr = 32'h0;
        for (int m = 0; m < NUM_MASTERS; m++) begin
            if (next_grant_id == m[M_WIDTH-1:0]) begin
                next_is_write = m_axi_mosi[m].awvalid;
                next_req_addr = m_axi_mosi[m].awvalid ? m_axi_mosi[m].awaddr : m_axi_mosi[m].araddr;
            end
        end

        // Decodifica em qual Slave o endereco da transacao cai
        next_target_slave = '0;
        next_decode_err   = 1'b1;
        for (int i = 0; i < NUM_SLAVES; i++) begin
            if ((next_req_addr & SLAVE_MASK[i]) == SLAVE_BASE[i]) begin
                next_target_slave = i[S_WIDTH-1:0];
                next_decode_err   = 1'b0;
            end
        end
    end

    // Sinais do Master vencedor e resposta agregada
    axi_lite_mosi_t active_mosi;
    axi_lite_miso_t active_miso;

    wire aw_hsk = bus_busy && is_write  && !aw_done && active_mosi.awvalid && active_miso.awready;
    wire w_hsk  = bus_busy && is_write  && !w_done  && active_mosi.wvalid  && active_miso.wready;
    wire b_hsk  = bus_busy && is_write  && active_mosi.bready && active_miso.bvalid;
    wire ar_hsk = bus_busy && !is_write && !ar_done && active_mosi.arvalid && active_miso.arready;
    wire r_hsk  = bus_busy && !is_write && active_mosi.rready && active_miso.rvalid;

    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            grant_id      <= '0;
            rr_ptr        <= '0;
            bus_busy      <= 1'b0;
            is_write      <= 1'b0;
            target_slave  <= '0;
            decode_err    <= 1'b0;
            aw_done       <= 1'b0;
            w_done        <= 1'b0;
            ar_done       <= 1'b0;
            decerr_bvalid <= 1'b0;
            decerr_rvalid <= 1'b0;
        end else begin
            if (!bus_busy) begin
                aw_done       <= 1'b0;
                w_done        <= 1'b0;
                ar_done       <= 1'b0;
                decerr_bvalid <= 1'b0;
                decerr_rvalid <= 1'b0;

                if (found_req) begin
                    grant_id     <= next_grant_id;
                    bus_busy     <= 1'b1;
                    is_write     <= next_is_write;
                    target_slave <= next_target_slave;
                    decode_err   <= next_decode_err;

                    if (int'(next_grant_id) + 1 >= NUM_MASTERS)
                        rr_ptr <= '0;
                    else
                        rr_ptr <= next_grant_id + 1'b1;
                end
            end else begin
                // Registra conclusao individual de cada canal de endereco/dados
                if (aw_hsk) aw_done <= 1'b1;
                if (w_hsk)  w_done  <= 1'b1;
                if (ar_hsk) ar_done <= 1'b1;

                // Tratamento do Default Slave para enderecos invalidos (DECERR = 2'b11)
                if (decode_err) begin
                    if (is_write) begin
                        if (!decerr_bvalid && ((aw_done || aw_hsk) && (w_done || w_hsk)))
                            decerr_bvalid <= 1'b1;
                        else if (b_hsk)
                            decerr_bvalid <= 1'b0;
                    end else begin
                        if (!decerr_rvalid && (ar_done || ar_hsk))
                            decerr_rvalid <= 1'b1;
                        else if (r_hsk)
                            decerr_rvalid <= 1'b0;
                    end
                end

                // Libera o barramento quando a resposta (B ou R) completa ou se o Master entrar em reset
                if (b_hsk || r_hsk || !m_active[grant_id]) begin
                    bus_busy      <= 1'b0;
                    aw_done       <= 1'b0;
                    w_done        <= 1'b0;
                    ar_done       <= 1'b0;
                    decerr_bvalid <= 1'b0;
                    decerr_rvalid <= 1'b0;
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // 2. Mux de Entrada: Seleciona o Master Vencedor (active_mosi)
    // ------------------------------------------------------------------------
    always_comb begin
        active_mosi = '0;
        for (int m = 0; m < NUM_MASTERS; m++) begin
            if (grant_id == m[M_WIDTH-1:0]) begin
                active_mosi           = m_axi_mosi[m];
                active_mosi.master_id = 8'(m);
            end
        end
    end

    // ------------------------------------------------------------------------
    // 3. Demux de Saida para os Slaves (s_axi_mosi) e Mux de Retorno (active_miso)
    // ------------------------------------------------------------------------
    always_comb begin
        s_axi_mosi  = '0;
        active_miso = '0;

        if (bus_busy) begin
            if (decode_err) begin
                // Endereco nao mapeado: Default Slave responde DECERR (2'b11)
                if (is_write) begin
                    active_miso.awready = !aw_done;
                    active_miso.wready  = !w_done;
                    active_miso.bvalid  = decerr_bvalid;
                    active_miso.bresp   = 2'b11; // DECERR
                end else begin
                    active_miso.arready = !ar_done;
                    active_miso.rvalid  = decerr_rvalid;
                    active_miso.rresp   = 2'b11; // DECERR
                    active_miso.rdata   = 32'd0;
                end
            end else begin
                // Conexao explicita por slave evitando multiplicacao dinamica em slices de vetores
                for (int s = 0; s < NUM_SLAVES; s++) begin
                    if (target_slave == s[S_WIDTH-1:0]) begin
                        if (is_write) begin
                            s_axi_mosi[s].master_id = active_mosi.master_id;
                            s_axi_mosi[s].awaddr    = active_mosi.awaddr;
                            s_axi_mosi[s].awvalid   = active_mosi.awvalid & !aw_done;
                            s_axi_mosi[s].wdata     = active_mosi.wdata;
                            s_axi_mosi[s].wstrb     = active_mosi.wstrb;
                            s_axi_mosi[s].wvalid    = active_mosi.wvalid  & !w_done;
                            s_axi_mosi[s].bready    = active_mosi.bready;
                            s_axi_mosi[s].arvalid   = 1'b0;
                            s_axi_mosi[s].rready    = 1'b0;

                            active_miso.awready = s_axi_miso[s].awready & !aw_done;
                            active_miso.wready  = s_axi_miso[s].wready  & !w_done;
                            active_miso.bresp   = s_axi_miso[s].bresp;
                            active_miso.bvalid  = s_axi_miso[s].bvalid;
                        end else begin
                            s_axi_mosi[s].master_id = active_mosi.master_id;
                            s_axi_mosi[s].araddr    = active_mosi.araddr;
                            s_axi_mosi[s].awvalid   = 1'b0;
                            s_axi_mosi[s].wvalid    = 1'b0;
                            s_axi_mosi[s].bready    = 1'b0;
                            s_axi_mosi[s].arvalid   = active_mosi.arvalid & !ar_done;
                            s_axi_mosi[s].rready    = active_mosi.rready;

                            active_miso.arready = s_axi_miso[s].arready & !ar_done;
                            active_miso.rdata   = s_axi_miso[s].rdata;
                            active_miso.rresp   = s_axi_miso[s].rresp;
                            active_miso.rvalid  = s_axi_miso[s].rvalid;
                        end
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // 4. Devolve a resposta exclusivamente para o Master dono da transacao
    // ------------------------------------------------------------------------
    always_comb begin
        m_axi_miso = '0;
        if (bus_busy) begin
            for (int m = 0; m < NUM_MASTERS; m++) begin
                if (grant_id == m[M_WIDTH-1:0]) begin
                    m_axi_miso[m] = active_miso;
                end
            end
        end
    end

endmodule
`default_nettype wire
