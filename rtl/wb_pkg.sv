package wb_pkg;

    typedef struct packed {
        logic [31:0] adr;
        logic [31:0] dat;
        logic [3:0]  sel;
        logic        we;
        logic        cyc;
    } wb_mosi_t;

    typedef struct packed {
        logic [31:0] rdt;
        logic        ack;
    } wb_miso_t;

endpackage
