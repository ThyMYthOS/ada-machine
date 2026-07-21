with Interfaces; use Interfaces;

package body STM32G474.GPIO
  with SPARK_Mode
is
   use STM32G474_PAC.GPIOA;

   procedure Configure_Output (Pin : Pin_Id) is
      Shift    : constant Natural := Natural (Pin) * 2;
      Mode_Now : constant Unsigned_32 := MODER;
   begin
      MODER := (Mode_Now and not (Unsigned_32 (3) * 2 ** Shift))
               or (Unsigned_32 (1) * 2 ** Shift);   --  "01" = output
   end Configure_Output;

   procedure Set_High (Pin : Pin_Id) is
   begin
      BSRR := Unsigned_32 (1) * 2 ** Natural (Pin);
   end Set_High;

   procedure Set_Low (Pin : Pin_Id) is
   begin
      BSRR := Unsigned_32 (1) * 2 ** (Natural (Pin) + 16);
   end Set_Low;

end STM32G474.GPIO;
