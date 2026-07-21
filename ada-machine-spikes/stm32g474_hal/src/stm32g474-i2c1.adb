with Interfaces; use Interfaces;

package body STM32G474.I2C1
  with SPARK_Mode
is
   use STM32G474_PAC.I2C1;

   procedure Enable (Cfg : Config := (others => <>)) is
      En1_Now, En2_Now, Mode_Now, Otype_Now, Pupd_Now, Afr_Now : Unsigned_32;
   begin
      --  Clock I2C1 and GPIOB (idempotent read-modify-write, like
      --  RP2040.I2C0.Enable's reset bring-up).
      En1_Now := STM32G474_PAC.RCC.APB1ENR1;
      STM32G474_PAC.RCC.APB1ENR1 := En1_Now or STM32G474_PAC.RCC.APB1ENR1_I2C1EN;
      En2_Now := STM32G474_PAC.RCC.AHB2ENR;
      STM32G474_PAC.RCC.AHB2ENR := En2_Now or STM32G474_PAC.RCC.AHB2ENR_GPIOBEN;

      --  Route PB6 (SCL) / PB7 (SDA) through I2C1's alternate function:
      --  AF mode, open-drain (I2C's electrical spec -- push-pull would
      --  drive instead of release the bus), weak pull-up (bring-up
      --  only; external pulls are still recommended in production, same
      --  caveat RP2040.I2C0.Enable documents).
      Mode_Now := STM32G474_PAC.GPIOB.MODER;
      STM32G474_PAC.GPIOB.MODER :=
        (Mode_Now and not (Unsigned_32 (16#F#) * 2 ** 12))
        or (Unsigned_32 (16#A#) * 2 ** 12);            --  pins 6,7 -> "10" AF

      Otype_Now := STM32G474_PAC.GPIOB.OTYPER;
      STM32G474_PAC.GPIOB.OTYPER :=
        Otype_Now or (Unsigned_32 (1) * 2 ** 6) or (Unsigned_32 (1) * 2 ** 7);

      Pupd_Now := STM32G474_PAC.GPIOB.PUPDR;
      STM32G474_PAC.GPIOB.PUPDR :=
        (Pupd_Now and not (Unsigned_32 (16#F#) * 2 ** 12))
        or (Unsigned_32 (16#5#) * 2 ** 12);             --  pins 6,7 -> "01" pull-up

      Afr_Now := STM32G474_PAC.GPIOB.AFRL;
      STM32G474_PAC.GPIOB.AFRL :=
        (Afr_Now and not (Unsigned_32 (16#FF#) * 2 ** 24))
        or (Unsigned_32 (STM32G474_PAC.GPIOB.I2C1_AF) * 2 ** 24)
        or (Unsigned_32 (STM32G474_PAC.GPIOB.I2C1_AF) * 2 ** 28);

      CR1 := 0;                          --  disable while reconfiguring

      --  Placeholder bus timing (D8, native config) -- re-derive with
      --  STM32CubeMX's I2C timing calculator against the actual core
      --  clock before real hardware bring-up; see stm32g474_pac-i2c1.ads.
      TIMINGR := 16#2000_090E#;

      --  Own address: OA1[7:1] takes the unshifted 7-bit address
      --  left-shifted by one (Machine.I2C.Address_7_Bit is documented
      --  unshifted, §7.2); OA1MODE left at 0 (7-bit mode).
      OAR1 := (Unsigned_32 (Cfg.Own_Address) * 2) or OAR1_OA1EN;

      CR1 := CR1_PE;
   end Enable;

   procedure Disable is
   begin
      CR1 := 0;
   end Disable;

   function Is_Address_Matched return Boolean is
      St : constant Unsigned_32 := ISR;
   begin
      return (St and ISR_ADDR) /= 0;
   end Is_Address_Matched;

   function Is_Read_From_Master return Boolean is
      St : constant Unsigned_32 := ISR;
   begin
      return (St and ISR_DIR) /= 0;
   end Is_Read_From_Master;

   procedure Ack_Address is
   begin
      ICR := ICR_ADDRCF;
   end Ack_Address;

   function Can_Pop return Boolean is
      St : constant Unsigned_32 := ISR;
   begin
      return (St and ISR_RXNE) /= 0;
   end Can_Pop;

   procedure Pop (Data : out Machine.Byte; Status : in out Machine.I2C.Bus_Status) is
      Raw : Unsigned_32;
   begin
      Data := 0;
      if Status /= Machine.I2C.Ok then
         return;                              --  chained: skip if pending
      end if;
      Raw  := RXDR;
      Data := Machine.Byte (Raw and 16#FF#);
   end Pop;

   function Can_Push return Boolean is
      St : constant Unsigned_32 := ISR;
   begin
      return (St and ISR_TXIS) /= 0;
   end Can_Push;

   procedure Push (Data : Machine.Byte; Status : in out Machine.I2C.Bus_Status) is
   begin
      if Status /= Machine.I2C.Ok then
         return;                              --  chained: skip if pending
      end if;
      TXDR := Unsigned_32 (Data);
   end Push;

   function Is_Stop return Boolean is
      St : constant Unsigned_32 := ISR;
   begin
      return (St and ISR_STOPF) /= 0;
   end Is_Stop;

   procedure Clear_Stop is
   begin
      ICR := ICR_STOPCF;
   end Clear_Stop;

end STM32G474.I2C1;
