with System;
with System.Storage_Elements; use System.Storage_Elements;
with System.Machine_Code;     use System.Machine_Code;
with Interfaces;              use Interfaces;

package body MSS_Clock is

   --  Section bounds exported by rts_support_mpfs/ld/place-lim.ld.
   Code_Start : constant Storage_Element
     with Import, Convention => Asm, External_Name => "__switch_code_start";
   Code_End   : constant Storage_Element
     with Import, Convention => Asm, External_Name => "__switch_code_end";
   Code_Load  : constant Storage_Element
     with Import, Convention => Asm, External_Name => "__switch_code_load";

   Is_Prepared : Boolean := False;

   ------------------------------------------------------------------
   --  Registers touched by the switch.
   ------------------------------------------------------------------

   --  Verified: the L2 cache controller base, from the PolarFire SoC
   --  memory-hierarchy documentation. WayEnable sets the cache/LIM boundary,
   --  so writing it moves LIM -- the canonical reason this code cannot run
   --  from LIM (RTS-POLARFIRE.md 1.2.1, 6.4).
   L2_Controller_Base : constant := 16#0201_0000#;
   L2_Way_Enable      : constant := L2_Controller_Base + 16#08#;

   --  UNVERIFIED: the MSS clock-configuration register address must be taken
   --  from the MSS Technical Reference Manual, or better, from the MSS
   --  Configurator XML's mss_pll section via the generator of
   --  RTS-POLARFIRE.md 4.3. It is deliberately left as a named constant with
   --  this marker rather than guessed at, so a reader cannot mistake it for a
   --  checked value.
   MSS_Clock_Config : constant := 16#0000_0000#;  --  UNVERIFIED - see above

   procedure Poke (Addr : Integer_Address; Value : Unsigned_32) is
      Reg : Unsigned_32 with Volatile, Import,
                             Address => To_Address (Addr);
   begin
      Reg := Value;
   end Poke;

   ------------------------------------------------------------------
   --  Switch -- runs from DTIM
   ------------------------------------------------------------------

   procedure Switch is
   begin
      --  Give one more L2 way to cache, shrinking LIM. Any code still
      --  executing from the vanishing region would fault here; this routine
      --  is in DTIM precisely so it cannot be that code.
      Poke (L2_Way_Enable, 1);

      if MSS_Clock_Config /= 0 then
         Poke (MSS_Clock_Config, 0);   --  UNVERIFIED register, see above
      end if;

      --  Let the new timing settle before returning to LIM-resident code.
      Asm ("fence", Volatile => True);
   end Switch;

   ------------------------------------------------------------------
   --  Prepare -- runs from LIM
   ------------------------------------------------------------------

   procedure Prepare is
      Run  : constant Integer_Address := To_Integer (Code_Start'Address);
      Stop : constant Integer_Address := To_Integer (Code_End'Address);
      Load : constant Integer_Address := To_Integer (Code_Load'Address);
   begin
      for Offset in 0 .. Storage_Offset (Stop - Run) - 1 loop
         declare
            Src : Unsigned_8 with Volatile, Import,
                     Address => To_Address (Load) + Offset;
            Dst : Unsigned_8 with Volatile, Import,
                     Address => To_Address (Run) + Offset;
         begin
            Dst := Src;
         end;
      end loop;

      --  DTIM now holds instructions the I-cache has never seen; fence.i is
      --  mandatory before executing them. This is why the E51 arch string
      --  includes zifencei (CONTRACT.md 7.9).
      Asm ("fence.i", Volatile => True);
      Is_Prepared := True;
   end Prepare;

   function Prepared return Boolean is (Is_Prepared);

end MSS_Clock;
