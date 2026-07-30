--  MSS clock reconfiguration for the E51 monitor core.
--
--  Why this exists as its own package: `pragma Linker_Section` requires a
--  LIBRARY-LEVEL entity, so the switch sequence cannot be a nested subprogram
--  of the main procedure.
--
--  Why it lives in DTIM: reprogramming the MSS clock changes L2 timing, so a
--  routine executing from L2 LIM would be reconfiguring the memory it is
--  fetching from. Microchip reserves 1 KB of the E51 DTIM at 0x01001c00 for
--  precisely this ("switch_code_dtim"). Same argument applies to changing L2
--  WayEnable, which moves LIM itself.
package MSS_Clock is

   --  The switch sequence. Resident in the reserved DTIM tail; must be copied
   --  there and fenced before being called -- see Prepare below.
   procedure Switch;
   pragma Linker_Section (Switch, ".switch_code");

   --  Copies .switch_code from its load address in LIM to its run address in
   --  DTIM and issues fence.i. Must run BEFORE Switch is called. This one
   --  stays in LIM: it is not affected by the reconfiguration it enables.
   procedure Prepare;

   function Prepared return Boolean;

end MSS_Clock;
