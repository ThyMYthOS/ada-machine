--  Test program for mpfs_pac
--  This program verifies that the generated PAC compiles and can be used

with MPFS_MSS;
with MPFS_MSS.CPU_Core_Complex;
with System;

procedure Pac_Test is
   use type System.Address;

   --  Test accessing a peripheral
   H0_Cause : aliased MPFS_MSS.UInt8
     with Import, Address => MPFS_MSS.BUS_ERROR_UNIT_H0_Base;

   --  Test accessing a register with bit fields
   Cache_Config : MPFS_MSS.CPU_Core_Complex.CONFIG_Register
     with Volatile_Full_Access;

   --  Test accessing a 64-bit register
   H0_Value : aliased MPFS_MSS.UInt64
     with Import, Address => System'To_Address (16#1700008#);

   --  Test accessing a peripheral through the generated type
   Cache_Ctrl : MPFS_MSS.CPU_Core_Complex.CACHE_CTRL_Peripheral
     with Import, Address => MPFS_MSS.CACHE_CTRL_Base;

begin
   --  Test 1: Verify base addresses are defined
   pragma Assert (MPFS_MSS.BUS_ERROR_UNIT_H0_Base = System'To_Address (16#1700000#));
   pragma Assert (MPFS_MSS.CACHE_CTRL_Base = System'To_Address (16#2010000#));

   --  Test 2: Verify register access works
   H0_Cause := 0;
   H0_Value := 0;

   --  Test 3: Verify bit field access works
   Cache_Config.BANKS := 4;
   Cache_Config.WAYS := 16;
   Cache_Config.SETS := 9;
   Cache_Config.BYTES := 6;

   --  Test 4: Verify peripheral access works
   Cache_Ctrl.CONFIG.BANKS := 4;
   Cache_Ctrl.WAY_ENABLE := 0;

   --  Test 5: Verify boolean fields work (if any)
   --  The SVD doesn't have boolean fields in the tested peripherals

   --  Test 6: Verify derived peripherals work
   declare
      H1_Periph : MPFS_MSS.CPU_Core_Complex.BUS_ERROR_UNIT_H0_Peripheral
        with Import, Address => MPFS_MSS.BUS_ERROR_UNIT_H1_Base;
   begin
      H1_Periph.CAUSE := 0;
   end;

   --  Success - all tests passed
   null;
end Pac_Test;
