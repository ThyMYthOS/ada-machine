/*
 * mpfs-memory.ld -- the one MEMORY block shared by every Memory_Profile
 * and every partition (RTS-POLARFIRE.md S1.3, S6.1).
 *
 * Every ORIGIN below is a LITERAL: it *is* the SoC (RTS-POLARFIRE.md S1.2,
 * S1.3 table) -- a base address does not change with how a leaf is
 * configured, only with which chip it targets, and this crate targets
 * exactly one chip.
 *
 * Every LENGTH that is not fixed by the SoC itself is a SYMBOL, supplied
 * by the leaf via -Wl,--defsym= (CONTRACT.md S4, symbol names pinned
 * there). Lengths vary because the memory system genuinely is
 * configuration, not because the hardware is unclear about it:
 *   - the L2 is 16 ways of 128 KB, partitioned at run time into cache /
 *     LIM / scratchpad ways (RTS-POLARFIRE.md S1.2.1) -- LIM and
 *     scratchpad lengths follow that partition;
 *   - ITIM/DTIM are a cache/SRAM split, per hart, private
 *     (RTS-POLARFIRE.md S1.4) -- their lengths follow which hart this
 *     image owns, and are 0 (not omitted) for every hart it does not;
 *   - DDR may not be present at all, and each 32-bit alias's length
 *     follows DDR_Present/DDR_*_KB.
 * A LENGTH of 0 is deliberate, not a placeholder: `ld` still lists a
 * zero-length region in the map, so placing anything in a region this
 * image does not own is a link-time "region ... overflowed" error rather
 * than a silently accepted image (RTS-POLARFIRE.md S1.4, S9).
 *
 * `ld` enforces region *overflow*; it does not check region *overlap*,
 * including between the local-memory windows below and including across
 * two separately-linked AMP partitions (RTS-POLARFIRE.md S6.3). Overlap
 * checking belongs in Ada, in MPFS.System_Map, as
 * pragma Compile_Time_Error -- not here.
 */

MEMORY
{
  /*  Non-volatile boot source. (rx): never a placement for writable data.  */
  envm        (rx)  : ORIGIN = 0x20220100, LENGTH = MPFS_ENVM_LENGTH

  /*  E51-only local data window (L1-D cache/SRAM split).  */
  /*  MPFS_DTIM_LENGTH is the WHOLE E51 DTIM; the reserved switch-code tail
   *  is carved off its top, so the two regions cannot overlap however
   *  MPFS_DTIM_LENGTH is configured.  */
  dtim        (rwx) : ORIGIN = 0x01000000,
                      LENGTH = MPFS_DTIM_LENGTH - MPFS_SWITCH_CODE_LENGTH

  /*  Six local-memory (L1-I cache/SRAM split) windows: one per hart,
   *  declared unconditionally -- names and bases are invariant, and a
   *  declared-but-unused window (LENGTH = 0) costs nothing (S1.4).  */
  /*  Reserved tail of the E51 DTIM. Microchip's own reference scripts carve
   *  1 KB off here for "switch code": anything that reconfigures the memory
   *  it would otherwise be executing from -- a clock/PLL switch (L2 timing
   *  moves with it) or an L2 WayEnable change (LIM itself moves). Such code
   *  must not live in LIM. Read-execute only.  */
  switch_code_dtim (rx) : ORIGIN = 0x01000000 + MPFS_DTIM_LENGTH
                                   - MPFS_SWITCH_CODE_LENGTH,
                          LENGTH = MPFS_SWITCH_CODE_LENGTH

  e51_itim    (rwx) : ORIGIN = 0x01800000, LENGTH = MPFS_E51_ITIM_LENGTH
  u54_1_itim  (rwx) : ORIGIN = 0x01808000, LENGTH = MPFS_U54_1_ITIM_LENGTH
  u54_2_itim  (rwx) : ORIGIN = 0x01810000, LENGTH = MPFS_U54_2_ITIM_LENGTH
  u54_3_itim  (rwx) : ORIGIN = 0x01818000, LENGTH = MPFS_U54_3_ITIM_LENGTH
  u54_4_itim  (rwx) : ORIGIN = 0x01820000, LENGTH = MPFS_U54_4_ITIM_LENGTH

  /*  Generic alias for "whichever hart this image owns' ITIM": both
   *  ORIGIN and LENGTH are symbolic, so one placement script serves any
   *  hart instead of needing one variant per hart (S1.4, verified S9).  */
  local_itim  (rwx) : ORIGIN = MPFS_LOCAL_ITIM_ORIGIN,
                       LENGTH = MPFS_LOCAL_ITIM_LENGTH

  /*  L2, addressed as directly-addressable SRAM (the ways not enabled as
   *  cache). 1920 KB at reset, needing zero L2 configuration (S1.2.1).  */
  l2lim       (rwx) : ORIGIN = 0x08000000, LENGTH = MPFS_LIM_LENGTH

  /*  L2, addressed as pinned cache ways (cacheable, ~3x faster than LIM,
   *  0 at reset -- creating one takes ways away from LIM, S1.2.1).  */
  scratchpad  (rwx) : ORIGIN = 0x0A000000, LENGTH = MPFS_SCRATCHPAD_LENGTH

  /*  DDR, 32-bit aliases. LENGTH = 0 is the vendor's own idiom for
   *  "alias absent" when DDR_Present => False (S1.3).  */
  ddr_cached  (rwx) : ORIGIN = 0x80000000, LENGTH = MPFS_DDR_CACHED_LENGTH
  ddr_nc      (rwx) : ORIGIN = 0xC0000000, LENGTH = MPFS_DDR_NC_LENGTH
  ddr_wcb     (rwx) : ORIGIN = 0xD0000000, LENGTH = MPFS_DDR_WCB_LENGTH
}
