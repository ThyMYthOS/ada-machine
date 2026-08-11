/* GENERATED FILE -- HAND-WRITTEN STAND-IN (see ../README.md).
 *
 * Placement script for the "App_Smp" partition (U54 harts 1-2, SMP),
 * matching ../src/mpfs-system_map.ads: App_Smp_Base/App_Smp_Size,
 * cached-DDR-resident. Shared by both harts -- an SMP partition is one
 * image, so there is exactly one placement script regardless of hart
 * count (RTS-POLARFIRE.md §1.4: SMP cannot live in ITIM precisely
 * because ITIM is per-hart private; DDR has no such restriction). See
 * partition-monitor.ld for the INCLUDE-path assumption.
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
  } > ddr_cached

  .init  : { KEEP (*(.init)) }  > ddr_cached
  .rodata :
  {
    *(.rodata .rodata.* .gnu.linkonce.r*)
  } > ddr_cached

  .data :
  {
    *(.data .data.* .gnu.linkonce.d*)
    *(.sdata .sdata.* .srodata .srodata.*)
  } > ddr_cached

  .bss (NOLOAD) :
  {
    . = ALIGN (0x8);
    __bss_start = .;
    *(.sbss*) *(.bss .bss.*) *(COMMON)
    /* Per-hart stacks for harts 1-2 are carved out here by this
     * partition's own runtime (RTS-POLARFIRE.md §7); out of scope for
     * this stand-in placement script. */
    __stack_start = .;
    . += DEFINED (__stack_size) ? __stack_size : (2 * 2 * 1024 * 1024);
    . = ALIGN (0x10);
    _end = .;
    __heap_start = .;
    __heap_end = ORIGIN (ddr_cached) + LENGTH (ddr_cached);
    __bss_end = .;
  } > ddr_cached

  /DISCARD/ : { *(.note.GNU-stack) *(.gnu.lto_*) }
}
