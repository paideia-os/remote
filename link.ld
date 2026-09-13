/* remote / rcopy linker script (mirrors tools/user/pdxsock/link.ld and
 * tools/user/mkfs.pdxfs/link.ld in the paideia-os monorepo -- R64v2
 * satellite-linking closure, paideia-os #1976). ENTRY(_start), .text
 * at 0x00400000, .data at 0x00600000, .bss contiguous with .data (no
 * fixed-address gap between .data and .bss -- see mkfs.pdxfs/link.ld's
 * own note: tools/verify-user-image-extent.sh in paideia-os fails the
 * build if a PT_LOAD reacquires a hole).
 *
 * Shared by both link steps in tools/build.sh (`remote` from
 * remote_client.o + kem.o + channel.o, and `rcopy` from rcopy.o +
 * kem.o + channel.o) -- each is its own independent `ld` invocation
 * against this same script, so there is exactly one `_start` symbol
 * per link.
 */

OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

PHDRS
{
    text PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    . = 0x00400000;

    .text : ALIGN(4K) {
        KEEP(*(.text._start))
        *(.text .text.*)
    } :text

    .rodata : ALIGN(8) {
        *(.rodata .rodata.*)
    } :text

    . = 0x00600000;

    .data : ALIGN(4K) {
        *(.data .data.*)
    } :data

    .bss (NOLOAD) : ALIGN(4K) {
        *(COMMON)
        *(.bss .bss.*)
        . = ALIGN(4K);
    } :data

    /DISCARD/ : {
        *(.comment)
        *(.eh_frame*)
        *(.note.*)
    }
}
