pragma Style_Checks (Off);
pragma Ada_2022;
pragma Restrictions (No_Elaboration_Code);

with MPFS_MSS_Config;
with MPFS_MSS.CFG_DDR_SGMII_PHY;
with MPFS_MSS.CPU_Core_Complex;
with MPFS_MSS.IOSCBCFG;
with MPFS_MSS.IOSCB_MUX_MSS;
with MPFS_MSS.IOSCB_MUX_SGMII;
with MPFS_MSS.IOSCB_PLL_MSS;
with MPFS_MSS.IOSCB_PLL_DDR;
with MPFS_MSS.MMUART;
with MPFS_MSS.SCB_REGS;
with MPFS_MSS.SYSREG;
with MPFS_MSS_Init.CPU;

package body MPFS_MSS_Init is

   CFG_DDR_SGMII_PHY renames MPFS_MSS.CFG_DDR_SGMII_PHY.CFG_DDR_SGMII_PHY_Periph;
   IOSCBCFG renames MPFS_MSS.IOSCBCFG.IOSCBCFG_Periph;
   IOSCB_MUX_MSS renames MPFS_MSS.IOSCB_MUX_MSS.IOSCB_MUX_MSS_Periph;
   IOSCB_MUX_SGMII renames MPFS_MSS.IOSCB_MUX_SGMII.IOSCB_MUX_SGMII_Periph;
   IOSCB_PLL_MSS renames MPFS_MSS.IOSCB_PLL_MSS.IOSCB_PLL_MSS_Periph;
   IOSCB_PLL_DDR renames MPFS_MSS.IOSCB_PLL_DDR.IOSCB_PLL_DDR_Periph;
   MMUART0 renames MPFS_MSS.MMUART.MMUART0_LO_Periph;
   SCB_REGS renames MPFS_MSS.SCB_REGS.SCB_REGS_Periph;
   SYSREG renames MPFS_MSS.SYSREG.SYSREG_Periph;
   BUS_ERROR_UNIT_H0 renames MPFS_MSS.CPU_Core_Complex.BUS_ERROR_UNIT_H0_Periph;

   PLL_INIT_AND_OUT_OF_RESET : constant := 16#0000_0003#;

   type Cycle is range 0 .. 2**64 - 1;
   --  FIXME (RTS-PRODUCTION.md A7 Step 2): computed from the wrong clock.
   --  10e6 is not the 80 MHz boot clock this runs under before the PLL
   --  switch below, so this is NOT actually 500 ns -- preserved unchanged
   --  from the reference rather than silently corrected; every delay in
   --  this sequence inherits the same error. (MPFS_MSS_Config.Clocks does not
   --  help here: it gives the post-switch target frequencies, not the
   --  80 MHz boot-time SCB clock this delay actually runs under.)
   DELAY_CYCLES_500_NS : constant Cycle :=
     Cycle (0.0000005 * 10e6);
   procedure Delay_Cycles (Cycles : Cycle) is
      End_Cycle : constant Cycle := Cycle (CPU.Rdcycle) + Cycles;
   begin
      while Cycle (CPU.Rdcycle) < End_Cycle loop
         null;
      end loop;
   end Delay_Cycles;

   procedure Set_RTC_Divisor is
   begin
      SYSREG.RTC_CLOCK_CR.ENABLE := False;
      SYSREG.RTC_CLOCK_CR.PERIOD := MPFS_MSS_Config.RTC_CLOCK_CR_Value.PERIOD;
      SYSREG.RTC_CLOCK_CR.ENABLE := True;
   end Set_RTC_Divisor;

   procedure Initialize is
   begin
      --  Init L2 cache
      --pragma Compile_Time_Error (MPFS.Memory_Map.Hw_Cache.WAY_ENABLE < 16, "Invalid cache way enable setting");

      --  mstatus.MIE and mie are already cleared by start.S, before this
      --  hart can even reach main -- not redone here. mstatus.MPIE and mip
      --  are not touched by start.S, so those still are.
      CPU.Clear_Mstatus_Bits (CPU.Mstatus_MPIE);
      CPU.Write_Mip_Bits (0);

      --  Load virtual ROM -- not implemented (RTS-PRODUCTION.md A7 Step 2).
      --  #define VIRTUAL_BOOTROM_BASE_ADDR   0x20003120UL  -> SYSREG.BOOT_ROM0'Address
      --  const uint32_t rom[NB_BOOT_ROM_WORDS] =
      --  {
      --     0x00000513U,    /* li a0, 0 */
      --     0x34451073U,    /* csrw mip, a0 */
      --     0x10500073U,    /* wfi */
      --     0xFF5FF06FU,    /* j 0x20003120 */
      --     0xFF1FF06FU,    /* j 0x20003120 */
      --     0xFEDFF06FU,    /* j 0x20003120 */
      --     0xFE9FF06FU,    /* j 0x20003120 */
      --     0xFE5FF06FU     /* j 0x20003120 */
      --  };

      --  Initialize bus error unit (FIXME: for all harts)
      BUS_ERROR_UNIT_H0 :=
        (ENABLE    => 0,
         PLIC_INT  => 0,
         LOCAL_INT => 0,
         CAUSE     => 0,
         ACCRUED   => 0,
         VALUE     => 0);

      --  Initialize memory protection unit -- not implemented (Step 2).
      --  Initialize processor memory protection -- not implemented (Step 2).
      SYSREG.APBBUS_CR := MPFS_MSS_Config.APBBUS_CR_Value;

      SYSREG.GPIO_INTERRUPT_FAB_CR := MPFS_MSS_Config.GPIO_INTERRUPT_FAB_CR_Value;

      --  Configure north west corner PLL
      Set_RTC_Divisor;
      --  SCB access settings -- fixed, not in the XML (RTS-PRODUCTION.md
      --  A7 Step 3 generator docstring: a procedural/timeout value, not a
      --  per-board configuration).
      IOSCBCFG.TIMER :=
        (TIMEOUT => 16#80#, REQUEST_TIME => 160, Reserved_16_31 => 8);
      --  Release APB reset & turn on DFI clock -- likewise fixed, not in
      --  the XML.
      SYSREG.DFIAPB_CR := (CLOCKON => True, RESET => False, others => <>);

      --  Dynamic APB enables for slaves -- fixed, not in the XML (a
      --  bring-up access-enable step, not a steady-state configuration).
      CFG_DDR_SGMII_PHY.DDRPHY_STARTUP :=
        (DYNEN_APB_PLL      => (As_Array => False, Val => 3),
         DYNEN_SCB_PLL      => (As_Array => False, Val => 3),
         DYNEN_SCB_CFM      => True,
         DYNEN_SCB_IO_CALIB => True,
         DYNEN_SCB_BANKCNTL => True,
         others             => <>);
      --  Enable all dynamic enables.
      --  NOT derived from MPFS_MSS_Config: the XML's own DYN_CNTL snapshot
      --  has every *_DYNEN bit at 0 (dynamic APB access disabled again
      --  once bring-up finished) -- using that value here would remove
      --  the very access this sequence needs to reach the PLL registers
      --  at all. See generate_mpfs_config.py's docstring.
      CFG_DDR_SGMII_PHY.DYN_CNTL :=
        (REG_PLL_DYNEN             => True,
         REG_DLL_DYNEN             => True,
         REG_PVT_DYNEN             => True,
         REG_BC_DYNEN              => True,
         REG_CLKMUX_DYNEN          => True,
         REG_LANE0_DYNEN           => True,
         REG_LANE1_DYNEN           => True,
         REG_PVT_SOFT_RESET_PERIPH => True,
         others                    => <>);

      --  Configure IOMUX and I/O settings for bank 2 and 4, from the MSS
      --  Configurator XML (RTS-PRODUCTION.md A7 Step 3,
      --  generate_mpfs_config.py). This board's own design, not a
      --  transcription from an unrelated reference.
      SYSREG.IOMUX0_CR := MPFS_MSS_Config.IOMUX0_CR_Value;
      SYSREG.IOMUX1_CR := MPFS_MSS_Config.IOMUX1_CR_Value;
      SYSREG.IOMUX2_CR := MPFS_MSS_Config.IOMUX2_CR_Value;
      SYSREG.IOMUX3_CR := MPFS_MSS_Config.IOMUX3_CR_Value;
      SYSREG.IOMUX4_CR := MPFS_MSS_Config.IOMUX4_CR_Value;
      SYSREG.IOMUX5_CR := MPFS_MSS_Config.IOMUX5_CR_Value;
      SYSREG.IOMUX6_CR := MPFS_MSS_Config.IOMUX6_CR_Value;

      SYSREG.MSSIO_BANK4_IO_CFG_0_1_CR := MPFS_MSS_Config.MSSIO_BANK4_IO_CFG_0_1_CR_Value;
      SYSREG.MSSIO_BANK4_IO_CFG_2_3_CR := MPFS_MSS_Config.MSSIO_BANK4_IO_CFG_2_3_CR_Value;
      SYSREG.MSSIO_BANK4_IO_CFG_4_5_CR := MPFS_MSS_Config.MSSIO_BANK4_IO_CFG_4_5_CR_Value;
      SYSREG.MSSIO_BANK4_IO_CFG_6_7_CR := MPFS_MSS_Config.MSSIO_BANK4_IO_CFG_6_7_CR_Value;
      SYSREG.MSSIO_BANK4_IO_CFG_8_9_CR := MPFS_MSS_Config.MSSIO_BANK4_IO_CFG_8_9_CR_Value;
      SYSREG.MSSIO_BANK4_IO_CFG_10_11_CR := MPFS_MSS_Config.MSSIO_BANK4_IO_CFG_10_11_CR_Value;
      SYSREG.MSSIO_BANK4_IO_CFG_12_13_CR := MPFS_MSS_Config.MSSIO_BANK4_IO_CFG_12_13_CR_Value;
      SYSREG.MSSIO_BANK2_IO_CFG_0_1_CR := MPFS_MSS_Config.MSSIO_BANK2_IO_CFG_0_1_CR_Value;
      SYSREG.MSSIO_BANK2_IO_CFG_2_3_CR := MPFS_MSS_Config.MSSIO_BANK2_IO_CFG_2_3_CR_Value;
      SYSREG.MSSIO_BANK2_IO_CFG_4_5_CR := MPFS_MSS_Config.MSSIO_BANK2_IO_CFG_4_5_CR_Value;
      SYSREG.MSSIO_BANK2_IO_CFG_6_7_CR := MPFS_MSS_Config.MSSIO_BANK2_IO_CFG_6_7_CR_Value;
      SYSREG.MSSIO_BANK2_IO_CFG_8_9_CR := MPFS_MSS_Config.MSSIO_BANK2_IO_CFG_8_9_CR_Value;
      SYSREG.MSSIO_BANK2_IO_CFG_10_11_CR := MPFS_MSS_Config.MSSIO_BANK2_IO_CFG_10_11_CR_Value;
      SYSREG.MSSIO_BANK2_IO_CFG_12_13_CR := MPFS_MSS_Config.MSSIO_BANK2_IO_CFG_12_13_CR_Value;

      --  Set bank2 and 4 volts
      SCB_REGS.MSSIO_BANK2_CFG_CR := MPFS_MSS_Config.MSSIO_BANK2_CFG_CR_Value;
      SCB_REGS.MSSIO_BANK4_CFG_CR := MPFS_MSS_Config.MSSIO_BANK4_CFG_CR_Value;

      --  Enter Dynamic Enable mode -- a fixed four-step handshake, not a
      --  per-board configuration; not in the XML.
      SCB_REGS.MSSIO_CONTROL_CR :=
        (MSS_DCE         => 7,
         MSS_CORE_UP     => True,
         MSS_FLASH_VALID => False,
         MSS_IO_EN       => False,
         others          => <>);
      Delay_Cycles (DELAY_CYCLES_500_NS);
      SCB_REGS.MSSIO_CONTROL_CR :=
        (MSS_DCE         => 0,
         MSS_CORE_UP     => True,
         MSS_FLASH_VALID => False,
         MSS_IO_EN       => False,
         others          => <>);
      Delay_Cycles (DELAY_CYCLES_500_NS);
      SCB_REGS.MSSIO_CONTROL_CR :=
        (MSS_DCE         => 0,
         MSS_CORE_UP     => True,
         MSS_FLASH_VALID => True,
         MSS_IO_EN       => False,
         others          => <>);
      Delay_Cycles (DELAY_CYCLES_500_NS);
      SCB_REGS.MSSIO_CONTROL_CR :=
        (MSS_CORE_UP     => True,
         MSS_FLASH_VALID => True,
         MSS_IO_EN       => True,
         others          => <>);

      --  Setup SGMII -- not implemented (sgmii_setup in the reference).

      --  Setup the MSS PLL.
      --
      --    9.2 Power on procedure for the MSS PLL clock
      --    During POR: PLL held in power down, clk_standby selected.
      --    1) mssclk_mux_sel_int<0>=0, powerdown_int_b=0, clk_standby_sel=0
      --       -- PLL powered down, clk_standby selected.
      --    2) powerdown_int_b=1, divq0_int_en=1 -- PLL powers up, lock
      --       asserts when locked.
      --    3) mssclk_mux_sel_int<0>=1 -- MSS PLL clock sent to MSS.
      --    4) On boot-auth complete: mssclk_mux_sel_int<0>=0 (select
      --       clk_standby), then powerdown_int_b=0 (power down the PLL).
      --    5) Write new PLL parameters, powerdown_int_b=1, wait for LOCK.
      --    6) Enable all 4 PLL outputs.
      --    7) mssclk_mux_sel_int<0>=1 -- select the MSS PLL clock.

      --  PLL_INIT_AND_OUT_OF_RESET is a fixed "bring out of reset" value
      --  (SOFT_RESET = 3), not a per-board configuration; the XML has a
      --  same-named SOFT_RESET register under the sgmii_pll/ddr_pll
      --  clock-mux blocks, but with unrelated fields (NV_MAP/V_MAP/
      --  PERIPH/BLOCKID) -- a name collision across SCB slave blocks that
      --  all share this register name by convention, not this one.
      IOSCB_PLL_DDR.SOFT_RESET := PLL_INIT_AND_OUT_OF_RESET;
      IOSCB_PLL_MSS.SOFT_RESET := PLL_INIT_AND_OUT_OF_RESET;

      --  4. Write new parameters to the MSS PLL, held powered down.
      --  PLL_CTRL is written twice (staged powered-down, then powered
      --  up): MPFS_MSS_Config.PLL_CTRL_Value is the steady state (powered
      --  up); this first write overrides only REG_POWERDOWN_B on top of
      --  it (Ada 2022 delta aggregate).
      IOSCB_PLL_MSS.PLL_CTRL :=
        (MPFS_MSS_Config.PLL_CTRL_Value with delta REG_POWERDOWN_B => False);

      --  PLL calibration register (PLL_CAL) is factory-set; not written.

      IOSCB_PLL_MSS.PLL_REF_FB := MPFS_MSS_Config.PLL_REF_FB_Value;
      IOSCB_PLL_MSS.PLL_DIV_0_1 := MPFS_MSS_Config.PLL_DIV_0_1_Value;
      IOSCB_PLL_MSS.PLL_DIV_2_3 := MPFS_MSS_Config.PLL_DIV_2_3_Value;
      IOSCB_PLL_MSS.PLL_CTRL2 := MPFS_MSS_Config.PLL_CTRL2_Value;
      IOSCB_PLL_MSS.PLL_FRACN := MPFS_MSS_Config.PLL_FRACN_Value;
      IOSCB_PLL_MSS.SSCG_REG_0 := MPFS_MSS_Config.SSCG_REG_0_Value;
      IOSCB_PLL_MSS.SSCG_REG_1 := MPFS_MSS_Config.SSCG_REG_1_Value;
      IOSCB_PLL_MSS.SSCG_REG_2 := MPFS_MSS_Config.SSCG_REG_2_Value;
      IOSCB_PLL_MSS.SSCG_REG_3 := MPFS_MSS_Config.SSCG_REG_3_Value;

      --  PLL phase registers.
      --  NOT derived from MPFS_MSS_Config -- see generate_mpfs_config.py's
      --  docstring for the precise finding: the XML's REG_OUT3_PHSINIT
      --  (declared width 3) carries value 0x8, which overflows exactly
      --  onto REG_LOADPHS_B's own bit. That is the "FIXME: XML says 0x8"
      --  this line used to carry, now narrowed to an exact cause rather
      --  than resolved -- the generator refuses to guess which field the
      --  vendor data actually meant, and so does this call site. Kept at
      --  the original reference's value.
      IOSCB_PLL_MSS.PLL_PHADJ :=
        (PLL_REG_SYNCREFDIV_EN     => True,
         PLL_REG_ENABLE_SYNCREFDIV => True,
         REG_OUT0_PHSINIT          => 0,
         REG_OUT1_PHSINIT          => 0,
         REG_OUT2_PHSINIT          => 0,
         REG_OUT3_PHSINIT          => 0,
         REG_LOADPHS_B             => True,
         others                    => <>);

      --  5) Start up the PLL with NEW parameters. Wait for LOCK.
      IOSCB_MUX_MSS.PLL_CKMUX := MPFS_MSS_Config.PLL_CKMUX_Value;

      --  MSS clock mux selection stays at its reset value (0) here; the
      --  glitchless mux is switched to the MSS PLL output after lock,
      --  below (step 7).

      IOSCB_MUX_SGMII.CLK_XCVR := MPFS_MSS_Config.CLK_XCVR_Value;
      IOSCB_MUX_MSS.BCLKMUX := MPFS_MSS_Config.BCLKMUX_Value;
      IOSCB_MUX_MSS.FMETER_ADDR := MPFS_MSS_Config.FMETER_ADDR_Value;
      IOSCB_MUX_MSS.FMETER_DATAW := MPFS_MSS_Config.FMETER_DATAW_Value;
      --  FMETER_DATAR is read-only; not written.

      Delay_Cycles (DELAY_CYCLES_500_NS);
      --  end of mss_mux_pre_mss_pll_config

      IOSCB_PLL_MSS.PLL_CTRL := MPFS_MSS_Config.PLL_CTRL_Value;

      --  Start up the PLL with NEW parameters. Wait for LOCK.
      --  FIXME (RTS-PRODUCTION.md A7 Step 2): no timeout -- a PLL that
      --  never locks hangs this hart here forever. Preserved unchanged.
      loop
         exit when IOSCB_PLL_MSS.PLL_CTRL.LOCK = True;
      end loop;

      --  6) Enable all 4 PLL outputs; 7) feed the MSS PLL clock through.
      --  This step must run from RAM, not eNVM: the eNVM clock changes as
      --  part of it, so the code performing the change cannot itself be
      --  fetched from eNVM at that moment. This crate is meant to be
      --  called from a RAM-resident caller (LIM, as A7 Step 1 requires for
      --  anything touching ENVM_CR/CLOCK_CONFIG_CR/MSSCLKMUX) -- it is not
      --  itself placed in a dedicated switch-code section the way
      --  clock_switch_e51 places its own switch, because unlike that
      --  crate this one does not need to survive being resident in the
      --  region whose timing it is changing (LIM timing is independent of
      --  the MSS/eNVM clock domains this changes).

      SYSREG.ENVM_CR := MPFS_MSS_Config.ENVM_CR_Value;

      --  Make sure the eNVM clock change lands before leaving RAM, since
      --  code is fetched from eNVM again once this procedure returns.
      CPU.Memory_Barrier;

      --  ENVM_CR.CLOCK_OKAY confirms the frequency change completed before
      --  the AHB frequency is bumped up.
      loop
         exit when SYSREG.ENVM_CR.CLOCK_OKAY = True;
      end loop;

      --  Change the MSS clock as required (MPFS_MSS_Config.Clocks.Cpu_Hz /
      --  Axi_Hz / Apb_Ahb_Hz are the resulting frequencies this divider
      --  combination produces, for anything downstream that needs them --
      --  e.g. a future console-divisor computation; CLOCK_CONFIG_CR_Value
      --  itself already carries the divider encoding).
      SYSREG.CLOCK_CONFIG_CR := MPFS_MSS_Config.CLOCK_CONFIG_CR_Value;

      --  Feed the MSS PLL clock to the MSS through the glitchless mux.
      IOSCB_MUX_MSS.MSSCLKMUX := MPFS_MSS_Config.MSSCLKMUX_Value;

      Set_RTC_Divisor;
      ----------------  end of the RAM-resident clock-switch step  --------

      --  Configure north west corner DDR -- not implemented (DDR out of
      --  scope here, RTS-PRODUCTION.md A7 Step 4.4).
      --  Initialize PLIC -- not implemented (A7 Step 4.2).

      SYSREG.SUBBLK_CLOCK_CR.MMUART :=
        (As_Array => True, Arr => [0 => True, others => <>]);
      SYSREG.SOFT_RESET_CR.MMUART :=
        (As_Array => True, Arr => [0 => False, others => <>]);

      MMUART0.LCR.DLAB := True;   --  Enable access to divisor registers
      MMUART0.DLR := (DLR => 81, others => <>);
      MMUART0.DMR := (DMR => 0, others => <>);
      MMUART0.LCR.DLAB := False;  --  Disable access to divisor registers
      MMUART0.MM0.EFBR := True;   --  Enable fractional baud rate generator
      MMUART0.DFR := (DFR => 30, others => <>);
      MMUART0.LCR.WLS := 3;       --  Set word length to 8 bits
   end Initialize;

end MPFS_MSS_Init;
