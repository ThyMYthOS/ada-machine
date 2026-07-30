--  Demonstrates application placement into the hart's tightly-integrated
--  memory. `pragma Linker_Section` requires a LIBRARY-LEVEL entity, so this
--  has to be a package -- a nested declaration inside the main subprogram is
--  rejected with "argument for pragma Linker_Section must be library level
--  entity". The section names are a contract with rts_support_mpfs's
--  placement scripts (.itim_text / .dtim_data).
package Fast_Path is

   procedure Tick;
   pragma Linker_Section (Tick, ".itim_text");

   Counter : Integer := 0;
   --  NOT placed in .dtim_data here: this image runs on a U54, and only the
   --  E51 has a configurable DTIM (RTS-POLARFIRE 1.4). light_mpfs therefore
   --  emits MPFS_DTIM_LENGTH=0, and attempting the placement fails the link
   --  with "region `dtim' overflowed by 16 bytes" -- the zero-length-region
   --  ownership check working as designed. With Hart_Class => e51 it links.

end Fast_Path;
