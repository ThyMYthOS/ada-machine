--  Boot-stage MSS bring-up (RTS-PRODUCTION.md A7, decision 1): a thin library
--  with no elaboration code, no Text_IO, no exceptions, no secondary stack,
--  no tasking -- consumed by a UBL main (boot mode 2) or by linked-in startup
--  (Boot_Role => primary) alike. It is NOT L0 runtime: it needs the hundreds
--  of registers README.md §10.1 says the runtime must not reach for.
--
--  STATUS: ported from a reference boot sequence adapted to Ada from
--  Microchip's reference C (user_boot_loader.adb at the Fraunhofer IIS
--  side, see that file's own history for provenance), NOT the output of
--  RTS-PRODUCTION.md A7's Step 0/Step 2 -- but A7 Step 3, the MSS
--  Configurator XML generator, now exists (generate_mpfs_config.py,
--  MPFS_MSS_Config) and every register value that is a genuine per-board
--  steady-state configuration is derived from it, not transcribed by
--  hand. What is NOT derived, and stays a fixed/hardcoded value, is
--  documented field by field in mpfs_mss_init.adb and in
--  generate_mpfs_config.py's own docstring -- each case is either
--  procedural (a bring-up access-enable step the XML only records the
--  post-bring-up idle value for, e.g. DYN_CNTL) or a genuine ambiguity
--  in the vendor data the generator refuses to guess at (PLL_PHADJ). The
--  known defects Step 2 still has to resolve:
--    - DELAY_CYCLES_500_NS is computed from the wrong clock (10e6, not the
--      80 MHz boot clock) -- gives ~5 cycles, not 500 ns worth.
--    - IOSCB_PLL_MSS.PLL_PHADJ.REG_LOADPHS_B is False (the original
--      reference's value): the XML's own REG_OUT3_PHSINIT field
--      overflows onto this exact bit, which is now a precisely located
--      ambiguity rather than a vague "XML says 0x8" -- still open.
--    - The PLL lock wait has no timeout.
--    - PMP/MPU, the virtual boot ROM and hart release are not
--      implemented (commented out in the reference).
--  Do not treat a successful build of this crate as that work being done.
package MPFS_MSS_Init is
   pragma Preelaborate;

   procedure Initialize;
   --  Runs the full bring-up sequence on the calling hart: clears pending
   --  interrupt state, brings up the MSS PLL and switches the MSS clock to
   --  it, then clocks/resets and programs MMUART0 at 115200 (APB clock
   --  dependent -- see the FIXME above on DELAY_CYCLES_500_NS, which this
   --  sequence's timing depends on throughout, not just in its own name).

end MPFS_MSS_Init;
