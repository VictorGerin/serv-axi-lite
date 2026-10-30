MEMORY
{
    BRAM (rwx) : ORIGIN = 0x00000000, LENGTH = 16K
}

SECTIONS
{
    .text : {
        *(.text.init)
        *(.text*)
        *(.rodata*)
    } > BRAM

    .data : {
        *(.data*)
        *(.sdata*)
    } > BRAM

    .bss : {
        *(.bss*)
        *(.sbss*)
        *(COMMON)
    } > BRAM
}
