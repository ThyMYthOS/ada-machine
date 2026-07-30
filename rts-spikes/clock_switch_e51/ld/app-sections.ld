/*  Contributed by THIS APPLICATION, not by the runtime.
 *
 *  The switch sequence must not execute from the memory it reconfigures
 *  (changing the MSS clock moves L2 timing; changing L2 WayEnable moves LIM
 *  itself), so it runs from the E51's DTIM. VMA in dtim, LMA in l2lim --
 *  MSS_Clock.Prepare copies it across and issues fence.i before calling.
 *
 *  The runtime knows only that a `dtim` region exists. The section name, the
 *  region choice and the copy are all this crate's decisions.
 */
  .switch_code : ALIGN(0x10)
  {
    __switch_code_start = .;
    *(.switch_code .switch_code.*)
    . = ALIGN(0x10);
    __switch_code_end = .;
  } > dtim AT> l2lim
  __switch_code_load = LOADADDR(.switch_code);
