// ============================================================================
// axi_lite_pkg.sv
// Pacote SystemVerilog com as structs de barramento AXI4-Lite:
//   - axi_lite_mosi_t : Master -> Slave (AW + W + AR + BREADY + RREADY + ID)
//   - axi_lite_miso_t : Slave -> Master (AWREADY + WREADY + B + ARREADY + R)
// ============================================================================
package axi_lite_pkg;

    // Sinais enviados pelo Master para o Slave
    typedef struct packed {
        // ID do Master (Hart/Core ID preenchido pelo Interconnect Multi-Master)
        logic [7:0]  master_id;
        // Write Address Channel (AW)
        logic [31:0] awaddr;
        logic        awvalid;
        // Write Data Channel (W)
        logic [31:0] wdata;
        logic [3:0]  wstrb;
        logic        wvalid;
        // Write Response Channel (B)
        logic        bready;
        // Read Address Channel (AR)
        logic [31:0] araddr;
        logic        arvalid;
        // Read Data Channel (R)
        logic        rready;
    } axi_lite_mosi_t;

    // Sinais enviados pelo Slave para o Master
    typedef struct packed {
        // Write Address Channel (AW)
        logic        awready;
        // Write Data Channel (W)
        logic        wready;
        // Write Response Channel (B)
        logic [1:0]  bresp;
        logic        bvalid;
        // Read Address Channel (AR)
        logic        arready;
        // Read Data Channel (R)
        logic [31:0] rdata;
        logic [1:0]  rresp;
        logic        rvalid;
    } axi_lite_miso_t;

endpackage
