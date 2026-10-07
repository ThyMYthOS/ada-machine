--  AVR: `cli` then `sleep` forever, built from the HAL's existing
--  primitives (no new inline assembly): Critical_Section.Enter is the
--  SREG-save-and-`cli`, Delays.Sleep_Idle arms SMCR.SE and executes
--  `sleep`. simavr treats sleeping with the I-bit clear as program end.
with ATmega328P.Critical_Section;
with ATmega328P.Delays;

package body Spike_Halt
  with SPARK_Mode => Off
is
   procedure Halt is
      Saved : constant ATmega328P.Critical_Section.Mask_State :=
        ATmega328P.Critical_Section.Enter;   --  never restored
      pragma Unreferenced (Saved);
   begin
      loop
         ATmega328P.Delays.Sleep_Idle;
      end loop;
   end Halt;
end Spike_Halt;
