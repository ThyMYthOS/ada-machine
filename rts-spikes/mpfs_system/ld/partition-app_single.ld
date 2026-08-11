/* GENERATED FILE -- HAND-WRITTEN STAND-IN (see ../README.md).
 *
 * Placement script for the "App_Single" partition (U54 hart 3), matching
 * ../src/mpfs-system_map.ads: App_Single_Base/App_Single_Size in cached
 * DDR, plus App_Single_Ipc_Base/App_Single_Ipc_Size in NON-cached DDR
 * (RTS-POLARFIRE.md §4.4: "coherence is not free" -- the IPC buffer gets
 * its own output section in the `ddr_nc` region, never folded into
 * `.data`/`.bss`, so a reviewer can see the coherence boundary in the
 * script). See partition-monitor.ld for the INCLUDE-path assumption.
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
    __stack_start = .;
    . += DEFINED (__stack_size) ? __stack_size : (2 * 1024 * 1024);
    . = ALIGN (0x10);
    _end = .;
    __heap_start = .;
    __heap_end = ORIGIN (ddr_cached) + LENGTH (ddr_cached);
    __bss_end = .;
  } > ddr_cached

  /* The IPC window (App_Single_Ipc_Base/Size, MPFS.System_Map §3): a
   * distinct output section in the non-cached alias, not part of this
   * partition's ordinary .data/.bss. A generator would additionally
   * assert here that SIZEOF(.ipc) does not exceed
   * MPFS.System_Map.App_Single_Ipc_Size -- `ld` checks region overflow
   * (RTS-POLARFIRE.md §6.3) but nothing ties SIZEOF(.ipc) to the value
   * this crate's own compile-time checks used, so this is left as a
   * documented gap rather than an unverified assertion. */
  .ipc (NOLOAD) : { *(.ipc .ipc.*) } > ddr_nc

  /DISCARD/ : { *(.note.GNU-stack) *(.gnu.lto_*) }
}
