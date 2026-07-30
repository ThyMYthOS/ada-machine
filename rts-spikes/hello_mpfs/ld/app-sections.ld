/*  Contributed by THIS APPLICATION, not by the runtime.
 *
 *  Fast_Path.Tick is placed in this hart's own ITIM for deterministic fetch.
 *  VMA in local_itim (whose origin the runtime derives from the hart mask),
 *  LMA in l2lim, so the image must copy it before calling.
 */
  .itim_text : ALIGN(0x10)
  {
    __itim_start = .;
    *(.itim_text .itim_text.*)
    . = ALIGN(0x10);
    __itim_end = .;
  } > local_itim AT> l2lim
  __itim_load = LOADADDR(.itim_text);
