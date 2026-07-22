with System.Machine_Code; use System.Machine_Code;

package body ATmega328P.Critical_Section
  with SPARK_Mode => Off  --  inline asm (in/out on __SREG__) is outside
                          --  the SPARK subset, same reasoning as
                          --  ATmega328P.Delays.Sleep_Idle's "sleep"
is

   function Enter return Mask_State is
      Saved : Interfaces.Unsigned_8;
   begin
      --  Read SREG, then disable, as one asm block (Volatile => True
      --  stops the compiler reordering/dropping either half) -- if an
      --  interrupt fires between the two instructions it still runs
      --  with the old (enabled) state, and "cli" still executes right
      --  after it returns, so the saved value stays a faithful snapshot
      --  of "the state Enter was called under".
      Asm ("in %0, __SREG__" & ASCII.LF & "cli",
           Outputs  => Interfaces.Unsigned_8'Asm_Output ("=r", Saved),
           Volatile => True);
      return Mask_State (Saved);
   end Enter;

   procedure Leave (Prev : Mask_State) is
      Value : constant Interfaces.Unsigned_8 := Interfaces.Unsigned_8 (Prev);
   begin
      --  Single instruction: restores the I-bit to whatever it was,
      --  never merely sets it -- correct even nested (README §14.4).
      Asm ("out __SREG__, %0",
           Inputs   => Interfaces.Unsigned_8'Asm_Input ("r", Value),
           Volatile => True);
   end Leave;

end ATmega328P.Critical_Section;
