with RP2040_PAC.Timer; use RP2040_PAC.Timer;
with Interfaces; use Interfaces;

package body RP2040.Clock
  with SPARK_Mode
is

   --  Safe 64-bit read of the free-running counter from its two 32-bit
   --  raw halves (pico-sdk's time_us_64 pattern): read the high half,
   --  then low, then high again; if high changed, a rollover of the low
   --  half happened mid-read, so retry with the new high half and a
   --  fresh low read.
   function Now return Ticks is
      Hi, Hi2, Lo : Unsigned_32;
   begin
      Hi := TIMERAWH;
      loop
         Lo  := TIMERAWL;
         Hi2 := TIMERAWH;
         exit when Hi2 = Hi;
         Hi := Hi2;
      end loop;
      --  Shift_Left/"or" in Unsigned_64, not Ticks: Interfaces.Shift_Left
      --  is only defined for Interfaces' own types, not the distinct
      --  user-defined "type Ticks is mod 2**64" -- convert once, at the
      --  end, since the two types share the same range exactly.
      return Ticks (Shift_Left (Unsigned_64 (Hi), 32) or Unsigned_64 (Lo));
   end Now;

end RP2040.Clock;
