with Interfaces; use Interfaces;

package body Mock_RNG
  with SPARK_Mode,
       Refined_State => (State => Next_Word)
is
   Next_Word : Unsigned_32 := 16#DEAD_BEEF#;

   procedure Set_Next_Word (W : Unsigned_32) is
   begin
      Next_Word := W;
   end Set_Next_Word;

   function Is_Ready return Boolean is (True);

   procedure Get_Word (Value : out Unsigned_32; Status : in out Rng_Status) is
   begin
      Value := 0;
      if Status /= Ok then
         return;                              --  chained: skip if pending
      end if;
      Value := Next_Word;
   end Get_Word;

end Mock_RNG;
