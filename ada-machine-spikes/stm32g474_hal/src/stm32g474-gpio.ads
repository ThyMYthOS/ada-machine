--  stm32g474-gpio.ads -- §6.4's shape, curated to GPIOA only (this
--  spike's status LED, PA5, is the only user -- §9 rule 1). Output only:
--  never configured as input, never read back.
with STM32G474_PAC.GPIOA;

package STM32G474.GPIO
  with Preelaborate, SPARK_Mode
is
   subtype Pin_Id is STM32G474.Pin_Id;

   procedure Configure_Output (Pin : Pin_Id)
     with Global => (In_Out => STM32G474_PAC.GPIOA.MODER);

   procedure Set_High (Pin : Pin_Id)
     with Inline_Always, Global => (Output => STM32G474_PAC.GPIOA.BSRR);
   procedure Set_Low  (Pin : Pin_Id)
     with Inline_Always, Global => (Output => STM32G474_PAC.GPIOA.BSRR);
end STM32G474.GPIO;
