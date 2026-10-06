with System.Machine_Code; use System.Machine_Code;

package body MPFS_MSS_Init.CPU is

   function Rdcycle return Interfaces.Unsigned_64 is
      Result : Interfaces.Unsigned_64;
   begin
      Asm ("csrr %0, cycle",
           Outputs  => Interfaces.Unsigned_64'Asm_Output ("=r", Result),
           Volatile => True);
      return Result;
   end Rdcycle;

   procedure Memory_Barrier is
   begin
      Asm ("fence", Volatile => True);
   end Memory_Barrier;

   procedure Clear_Mstatus_Bits (Bits : Interfaces.Unsigned_64) is
   begin
      Asm ("csrc mstatus, %0",
           Inputs   => Interfaces.Unsigned_64'Asm_Input ("r", Bits),
           Volatile => True);
   end Clear_Mstatus_Bits;

   procedure Write_Mie_Bits (Bits : Interfaces.Unsigned_64) is
   begin
      Asm ("csrw mie, %0",
           Inputs   => Interfaces.Unsigned_64'Asm_Input ("r", Bits),
           Volatile => True);
   end Write_Mie_Bits;

   procedure Write_Mip_Bits (Bits : Interfaces.Unsigned_64) is
   begin
      Asm ("csrw mip, %0",
           Inputs   => Interfaces.Unsigned_64'Asm_Input ("r", Bits),
           Volatile => True);
   end Write_Mip_Bits;

end MPFS_MSS_Init.CPU;
