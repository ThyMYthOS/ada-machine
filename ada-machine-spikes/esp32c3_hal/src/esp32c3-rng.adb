package body ESP32C3.RNG
  with SPARK_Mode
is

   procedure Get_Word (Value  : out Interfaces.Unsigned_32;
                       Status : in out Machine.RNG.Rng_Status)
   is
      Raw : Interfaces.Unsigned_32;
   begin
      Value := 0;
      if Status /= Machine.RNG.Ok then
         return;                              --  chained: skip if pending
      end if;
      Raw   := ESP32C3_PAC.SYSCON.RND_DATA;
      Value := Raw;
   end Get_Word;

end ESP32C3.RNG;
