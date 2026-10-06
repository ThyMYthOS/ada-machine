--  Build-only sanity check (see alire.toml): calls MPFS_MSS_Init.Initialize
--  and prints through the runtime's own console afterward, to prove the
--  crate compiles and links against the real riscv64-elf cross compiler.
--
--  Not a correctness check. Initialize reprograms MMUART0 directly at the
--  register level (raw THR writes, its own divisor/LCR setup) independently
--  of the runtime's own System.Text_IO console driver, which this hart's
--  Console => "mmuart0" configuration also owns -- the two are not
--  coordinated. Do not read anything into whether the Put_Line output below
--  appears cleanly; that is exactly the kind of double-init situation
--  README.md §10.3 flags, and resolving it is out of scope here.
with Ada.Text_IO; use Ada.Text_IO;
with MPFS_MSS_Config;
with MPFS_MSS_Init;

procedure Mpfs_Mss_Init_Test is
begin
   MPFS_MSS_Init.Initialize;
   --  Provenance stamp: which XML snapshot configured this image,
   --  readable on the console by anyone probing the board or
   --  comparing against a pinned hash (RTS-POLARFIRE.md §4.4's
   --  "stale XML" pattern -- this crate has no second, independent
   --  input to assert the pair against yet, so for now this is
   --  read-only provenance, not a cross-check). Also doubles as the
   --  console smoke test the raw 'A','B','C' bytes used to be.
   Put_Line ("MPFS XML v" & MPFS_MSS_Config.XML_Format_Version & " "
               & MPFS_MSS_Config.XML_SHA256 & ASCII.CR & ASCII.LF);
end Mpfs_Mss_Init_Test;
