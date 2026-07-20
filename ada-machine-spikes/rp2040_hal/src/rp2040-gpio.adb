with RP2040_PAC.SIO;        use RP2040_PAC.SIO;
with RP2040_PAC.IO_Bank0;   use RP2040_PAC.IO_Bank0;
with RP2040_PAC.Pads_Bank0; use RP2040_PAC.Pads_Bank0;
with Interfaces; use Interfaces;

package body RP2040.GPIO
  with SPARK_Mode
is

   function Mask (Pin : Pin_Id) return Unsigned_32 is
     (Shift_Left (1, Natural (Pin)));

   procedure Configure (Pin : Pin_Id; Dir : Direction; P : Pull := Floating)
   is
      --  Fully qualified: both IO_Bank0 and Pads_Bank0 are "use"d above,
      --  and both declare a Pin_Index subtype, so the bare name would be
      --  ambiguous -- "IO_Bank0.Pin_Index" as a shortened prefix (the
      --  original form here) isn't legal Ada; "use" gives direct
      --  visibility to the *contents* of a package, not a short alias
      --  for the package name itself.
      I : constant RP2040_PAC.IO_Bank0.Pin_Index :=
        RP2040_PAC.IO_Bank0.Pin_Index (Pin);
      A : constant RP2040_PAC.Pads_Bank0.Pin_Index :=
        RP2040_PAC.Pads_Bank0.Pin_Index (Pin);
      Pad : Unsigned_32 := PAD_IE or PAD_SCHMITT;   --  input path always on
   begin
      case P is
         when Floating  => null;
         when Pull_Up   => Pad := Pad or PAD_PUE;
         when Pull_Down => Pad := Pad or PAD_PDE;
      end case;
      Pads (A) := Pad;

      --  Route the pin through SIO (software-driven GPIO), then set
      --  direction via the SIO output-enable aliases (§6.4: one store).
      Pins (I).Ctrl := FUNCSEL_SIO;
      case Dir is
         when Input  => GPIO_OE_CLR := Mask (Pin);
         when Output => GPIO_OE_SET := Mask (Pin);
      end case;
   end Configure;

   procedure Set_High (Pin : Pin_Id) is
   begin
      GPIO_OUT_SET := Mask (Pin);
   end Set_High;

   procedure Set_Low (Pin : Pin_Id) is
   begin
      GPIO_OUT_CLR := Mask (Pin);
   end Set_Low;

   procedure Toggle (Pin : Pin_Id) is
   begin
      GPIO_OUT_XOR := Mask (Pin);
   end Toggle;

   function Is_High (Pin : Pin_Id) return Boolean is
      --  GPIO_IN read alone into a local first: SPARK requires a
      --  volatile read to be the whole right-hand side of an
      --  assignment/declaration, not combined with other operators in
      --  the same expression (SPARK RM 7.1.3(9)).
      In_Bits : constant Unsigned_32 := GPIO_IN;
   begin
      return (In_Bits and Mask (Pin)) /= 0;
   end Is_High;

end RP2040.GPIO;
