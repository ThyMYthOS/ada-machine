with Interfaces;

--  Own, minimal CSR primitives -- not System.BB.CPU_Specific. RTS-PRODUCTION.md
--  A7 decision 1: mpfs_mss_init is a boot-stage crate, not L0 runtime, so it
--  does not reach into runtime-internal System.BB.* units (README.md §10.1's
--  trusted-computing-base argument applies here too: this crate's own surface
--  should stay independently auditable from the runtime's).
package MPFS_MSS_Init.CPU is
   pragma Preelaborate;

   function Rdcycle return Interfaces.Unsigned_64 with Inline_Always;
   --  Zicntr "cycle" CSR, full 64 bits in one read on rv64.

   procedure Memory_Barrier with Inline_Always;
   --  Full fence (fence rw, rw).

   procedure Clear_Mstatus_Bits (Bits : Interfaces.Unsigned_64)
     with Inline_Always;
   procedure Write_Mie_Bits (Bits : Interfaces.Unsigned_64)
     with Inline_Always;
   procedure Write_Mip_Bits (Bits : Interfaces.Unsigned_64)
     with Inline_Always;

   Mstatus_MIE  : constant Interfaces.Unsigned_64 := 2#0000_1000#;
   Mstatus_MPIE : constant Interfaces.Unsigned_64 := 2#1000_0000#;

end MPFS_MSS_Init.CPU;
