with Interfaces; use Interfaces;

package body STM32G474.I2C1
  with SPARK_Mode
is
   use STM32G474_PAC.I2C1;

   --  TIMINGR for standard mode (100 kHz) with I2CCLK = 16 MHz: this HAL
   --  never configures a PLL, so the core clock is the reset-default
   --  HSI16, and I2C1SEL resets to PCLK1 = HSI16 (no RCC divider is
   --  touched). Fields: PRESC [31:28], SCLDEL [23:20], SDADEL [19:16],
   --  SCLH [15:8], SCLL [7:0]. Evaluated by hand against the I2C v2
   --  timing constraints (RM0440, I2C timing section) with the spec's
   --  worst-case standard-mode edges (tr 1000 ns, tf 300 ns, tSU;DAT
   --  250 ns, tHD;DAT 0, tVD;DAT 3450 ns), analog filter on, DNF = 0:
   --    tPRESC = (3+1)/16 MHz                   = 250 ns
   --    tSCLDEL = (4+1) * 250 ns = 1250 ns      >= tr + tSU;DAT = 1250 ns
   --    tSDADEL =  2    * 250 ns =  500 ns      in [tf - tAF(min) - 3*tI2CCLK,
   --                                                tVD;DAT - tr - tAF(max)
   --                                                - 4*tI2CCLK] ~ [62 ns, 1950 ns]
   --    tSCLL = (0x13+1) * 250 ns = 5.0 us      >= 4.7 us   (master only)
   --    tSCLH = (0x0F+1) * 250 ns = 4.0 us      >= 4.0 us   (master only)
   --  Not run through STM32CubeMX; if the board's real rise time or
   --  filter settings differ, recompute rather than reuse. A different
   --  core clock or bus speed needs a different value.
   Timing_Standard_16MHz : constant Unsigned_32 :=
     (Unsigned_32 (3)  * 2 ** 28)        --  PRESC
     or (Unsigned_32 (4)  * 2 ** 20)     --  SCLDEL
     or (Unsigned_32 (2)  * 2 ** 16)     --  SDADEL
     or (Unsigned_32 (15) * 2 ** 8)      --  SCLH
     or Unsigned_32 (19);                --  SCLL

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

      TIMINGR := Timing_Standard_16MHz;   --  D8, native config; derivation above

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
      --  A new transaction must not inherit a stale bus fault.
      ICR := ICR_ADDRCF or ICR_BERRCF or ICR_ARLOCF;
   end Ack_Address;

   function Can_Pop return Boolean is
      St : constant Unsigned_32 := ISR;
   begin
      return (St and ISR_RXNE) /= 0;
   end Can_Pop;

   procedure Pop (Data : out Machine.Byte; Status : in out Machine.I2C.Bus_Status) is
      St  : Unsigned_32;
      Raw : Unsigned_32;
   begin
      Data := 0;
      if Status /= Machine.I2C.Ok then
         return;                              --  chained: skip if pending
      end if;
      St := ISR;
      if (St and ISR_BERR) /= 0 then
         Status := Machine.I2C.Bus_Error;     --  flag cleared at the
                                              --  transaction boundary
      elsif (St and ISR_ARLO) /= 0 then
         Status := Machine.I2C.Arbitration_Lost;
      else
         Raw  := RXDR;
         Data := Machine.Byte (Raw and 16#FF#);
      end if;
   end Pop;

   function Can_Push return Boolean is
      St : constant Unsigned_32 := ISR;
   begin
      return (St and ISR_TXIS) /= 0;
   end Can_Push;

   procedure Push (Data : Machine.Byte; Status : in out Machine.I2C.Bus_Status) is
      St : Unsigned_32;
   begin
      if Status /= Machine.I2C.Ok then
         return;                              --  chained: skip if pending
      end if;
      St := ISR;
      if (St and ISR_BERR) /= 0 then
         Status := Machine.I2C.Bus_Error;     --  flag cleared at the
                                              --  transaction boundary
      elsif (St and ISR_ARLO) /= 0 then
         Status := Machine.I2C.Arbitration_Lost;
      else
         TXDR := Unsigned_32 (Data);
      end if;
   end Push;

   function Is_Stop return Boolean is
      St : constant Unsigned_32 := ISR;
   begin
      return (St and ISR_STOPF) /= 0;
   end Is_Stop;

   procedure Clear_Stop is
   begin
      --  End of transaction: also where BERR/ARLO raised by Pop/Push are
      --  cleared (fail clean, §7.1 rule 2), keeping those two write-free.
      ICR := ICR_STOPCF or ICR_BERRCF or ICR_ARLOCF;
   end Clear_Stop;

end STM32G474.I2C1;
