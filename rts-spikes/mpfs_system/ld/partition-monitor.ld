/* GENERATED FILE -- HAND-WRITTEN STAND-IN (see ../README.md).
 *
 * Placement script for the "Monitor" partition (E51, hart 0), matching
 * ../src/mpfs-system_map.ads: Monitor_Base/Monitor_Size, LIM-resident
 * (RTS-POLARFIRE.md §6.1's "generated placement scripts for
 * system_partition, one per partition"). ASSUMPTION: rts_support_mpfs's
 * ld/mpfs-memory.ld does not exist yet at the time this was written --
 * only reference *.ld.upstream copies are present under
 * rts_support_mpfs/ld/. The relative INCLUDE path below is CONTRACT.md's
 * pinned directory name (rts_support_mpfs/ld/) and RTS-POLARFIRE.md
 * §6.1's file name.
 */

INCLUDE ../../rts_support_mpfs/ld/mpfs-memory.ld

OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  .text :
  {
    KEEP (*(SORT_NONE(.start)))
    *(.text .text.* .gnu.linkonce.t*)
  } > l2lim

  .init  : { KEEP (*(.init)) }  > l2lim
  .rodata :
  {
    *(.rodata .rodata.* .gnu.linkonce.r*)
  } > l2lim

  .data :
  {
    *(.data .data.* .gnu.linkonce.d*)
    *(.sdata .sdata.* .srodata .srodata.*)
  } > l2lim

  .bss (NOLOAD) :
  {
    . = ALIGN (0x8);
    __bss_start = .;
    *(.sbss*) *(.bss .bss.*) *(COMMON)
    __stack_start = .;
    . += DEFINED (__stack_size) ? __stack_size : (2 * 1024 * 1024);
    . = ALIGN (0x10);
    _end = .;
    __heap_start = .;
    __heap_end = ORIGIN (l2lim) + LENGTH (l2lim);
    __bss_end = .;
  } > l2lim

  /DISCARD/ : { *(.note.GNU-stack) *(.gnu.lto_*) }
}
