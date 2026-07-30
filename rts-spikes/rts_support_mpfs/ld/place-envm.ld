/*
 * place-envm.ld -- Memory_Profile => envm. Adapted from this crate's
 * populated ld/common-RAM.ld.upstream: code executes in place (XIP) from
 * eNVM, the non-volatile boot source, so .text/.rodata/.init/.ctors/
 * .dtors/.eh_frame/.gcc_except_table are placed there with LMA = VMA (no
 * copy needed to *read* code out of ROM).
 *
 * eNVM is (rx) -- never writable (mpfs-memory.ld) -- so .data cannot live
 * there at run time. It is placed with its VMA in l2lim (writable SRAM,
 * usable at reset with no L2 configuration, RTS-POLARFIRE.md S1.2.1) and
 * its LMA in envm, immediately after .rodata, via "AT>". .bss, the
 * stacks and the heap have no LMA (NOLOAD) and go directly to l2lim.
 *
 * KNOWN GAP, reported rather than silently worked around: LMA != VMA for
 * .data means something must copy __data_load .. (in envm) to
 * __data_start .. __data_end (in l2lim) before it is first read. The
 * populated start-ram.S does not do this -- it only clears .bss. So this
 * placement is syntactically complete and link-clean, but a program built
 * against it would run with .data uninitialised (garbage/whatever l2lim
 * held) until that copy loop is added to the startup code, which is
 * outside this crate's scope (`src/start-ram.S` is populated, not
 * authored, and is not in the list of files task 4 asked this crate to
 * change). See this crate's README.md and the task report.
 */

INCLUDE mpfs-memory.ld

SEARCH_DIR(.)
__DYNAMIC  =  0;

_DEFAULT_STACK_SIZE = (2 * 1024 * 1024);

OUTPUT_ARCH("riscv")

ENTRY(_start_ram);

SECTIONS
{
  .text :
  {
    __text = .;
    KEEP (*(SORT_NONE(.start)))
    *(.text .text.* .gnu.linkonce.t*)
    *(.gnu.warning)
  } > envm

  .init  : { KEEP(*(.init)) } > envm
  .ctors : { KEEP(SORT_BY_NAME(*)(.ctors)) } > envm
  .dtors : { KEEP(SORT_BY_NAME(*)(.dtors)) } > envm

  .rodata :
  {
    *(.rdata)
    *(.rodata .rodata.* .gnu.linkonce.r*)
    . = ALIGN(0x4);
    __rom_end = .;
  } > envm

  .eh_frame_hdr :
  {
     __eh_frame_hdr = .;
    *(.eh_frame_hdr)
  } > envm

  .eh_frame  :
  {
    KEEP (*(.eh_frame))
  } > envm

  .gcc_except_table :
  {
    *(.gcc_except_table .gcc_except_table.*)
  } > envm

  .data :
  {
    __data = .;
    __data_start = .;
    *(.data .data.* .gnu.linkonce.d*)
  } > l2lim AT> envm

  .srodata ALIGN(4) : ALIGN(4) /* Align both virtual and load addresses */
  {
    PROVIDE( __global_pointer$ = . + 0x800 );
    *(.srodata.cst16)
    *(.srodata.cst8)
    *(.srodata.cst4)
    *(.srodata.cst2)
    *(.srodata .srodata.*)
  } > l2lim AT> envm

  .sdata ALIGN(4) : ALIGN(4) /* Align both virtual and load addresses */
  {
    *(.sdata .sdata.*)
    *(.gnu.linkonce.s.*)
  } > l2lim AT> envm

  .sdata2 ALIGN(4) : ALIGN(4) /* Align both virtual and load addresses */
  {
    *(.sdata2 .sdata2.*)
    *(.gnu.linkonce.s2.*)
  } > l2lim AT> envm

  __data_end = .;

  /* Size of all data sections (.data, .srodata, .sdata) in number of 32bit
   * words.
   */
  __data_words = (__data_end - __data_start) >> 2;

  /* Base address of all data sections in ROM. The startup code copies these
   * sections from __data_load (in ROM) to __data_start (in RAM).
   */
  __data_load = LOADADDR(.data);

  .bss (NOLOAD): {
   . = ALIGN(0x8);
   __bss_start = .;

   *(.sbss*)
   *(.gnu.linkonce.sb.*)
   *(.bss .bss.*)
   *(.gnu.linkonce.b.*)
   *(COMMON)

   /* Interrupt stacks. Statically allocated in System.BB.Interrupts */
   __interrupt_stack_start = .;
   *(.noinit.interrupt_stacks)
   . = ALIGN(0x10); /* Align stack to 128 bits as required in the ABI */
   __interrupt_stack_end = .;


   __stack_start = .;
   . += DEFINED (__stack_size) ? __stack_size : _DEFAULT_STACK_SIZE;
   . = ALIGN(0x10); /* Align stack to 128 bits as required in the ABI */
   __stack_end = .;

   _end = .;
   __heap_start = .;
   __heap_end = ORIGIN(l2lim) + LENGTH(l2lim);
   __bss_end = .;
  } > l2lim

   __bss_words = (__bss_end - __bss_start) >> 2;

  /* DWARF debug sections.
     Symbols in the DWARF debugging sections are relative to the beginning
     of the section so we begin them at 0.  */

  /* DWARF 1.  */
  .debug          0 : { *(.debug) }
  .line           0 : { *(.line) }

  /* GNU DWARF 1 extensions.  */
  .debug_srcinfo  0 : { *(.debug_srcinfo) }
  .debug_sfnames  0 : { *(.debug_sfnames) }

  /* DWARF 1.1 and DWARF 2.  */
  .debug_aranges  0 : { *(.debug_aranges) }
  .debug_pubnames 0 : { *(.debug_pubnames) }

  /* DWARF 2.  */
  .debug_info     0 : { *(.debug_info .gnu.linkonce.wi.*) }
  .debug_abbrev   0 : { *(.debug_abbrev) }
  .debug_line     0 : { *(.debug_line .debug_line.* .debug_line_end) }
  .debug_frame    0 : { *(.debug_frame) }
  .debug_str      0 : { *(.debug_str) }
  .debug_loc      0 : { *(.debug_loc) }
  .debug_macinfo  0 : { *(.debug_macinfo) }

  /* SGI/MIPS DWARF 2 extensions.  */
  .debug_weaknames 0 : { *(.debug_weaknames) }
  .debug_funcnames 0 : { *(.debug_funcnames) }
  .debug_typenames 0 : { *(.debug_typenames) }
  .debug_varnames  0 : { *(.debug_varnames) }

  /* DWARF 3.  */
  .debug_pubtypes 0 : { *(.debug_pubtypes) }
  .debug_ranges   0 : { *(.debug_ranges) }

  /* DWARF 5.  */
  .debug_addr     0 : { *(.debug_addr) }
  .debug_line_str 0 : { *(.debug_line_str) }
  .debug_loclists 0 : { *(.debug_loclists) }
  .debug_macro    0 : { *(.debug_macro) }
  .debug_names    0 : { *(.debug_names) }
  .debug_rnglists 0 : { *(.debug_rnglists) }
  .debug_str_offsets 0 : { *(.debug_str_offsets) }
  .debug_sup      0 : { *(.debug_sup) }

  .gnu.attributes 0 : { KEEP (*(.gnu.attributes)) }
  /DISCARD/ : { *(.note.GNU-stack) *(.gnu_debuglink) *(.gnu.lto_*) }
}
