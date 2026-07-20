with Interfaces; use Interfaces;
with Ada.Unchecked_Conversion;

--  §6.6: the spec is 100% SPARK; the body stays in SPARK_Mode too.
--  Ada.Unchecked_Conversion between same-size scalar types (To_I16/To_I8/
--  To_I64/To_U64, used for the datasheet's signed-reinterpretation tricks
--  and the ASR/ASL shift helpers built on them) is accepted by GNATprove --
--  it is not the kind of non-SPARK construct §6.6 needs an opt-out for.
package body BME280
  with SPARK_Mode
is

   use Machine;
   use type Machine.Regmap.Access_Status;

   --  Registers ------------------------------------------------------
   Reg_Id        : constant Regmap.Reg_Address := 16#D0#;
   Reg_Reset     : constant Regmap.Reg_Address := 16#E0#;
   Reg_Calib_00  : constant Regmap.Reg_Address := 16#88#;  --  T1..P9, 24 B
   Reg_Calib_H1  : constant Regmap.Reg_Address := 16#A1#;
   Reg_Calib_26  : constant Regmap.Reg_Address := 16#E1#;  --  H2..H6, 7 B
   Reg_Ctrl_Hum  : constant Regmap.Reg_Address := 16#F2#;
   Reg_Status    : constant Regmap.Reg_Address := 16#F3#;
   Reg_Ctrl_Meas : constant Regmap.Reg_Address := 16#F4#;
   Reg_Data      : constant Regmap.Reg_Address := 16#F7#;  --  8 B burst

   Chip_Id       : constant Byte := 16#60#;
   Reset_Command : constant Byte := 16#B6#;
   Mode_Forced   : constant Byte := 2#01#;

   --  Log events (deferred formatting: ids only) ---------------------
   Ev_Wrong_Id  : constant Log.Event_Id := 16#0001#;
   Ev_Bus_Fault : constant Log.Event_Id := 16#0002#;
   Ev_Timed_Out : constant Log.Event_Id := 16#0003#;

   --  H4/H5 are packed as 12-bit signed fields (datasheet 4.2.2); narrowing
   --  the type to their true bit width, rather than leaving them at the
   --  full 16 bits the register pair could otherwise hold, is what lets
   --  GNATprove bound the humidity formula below without guessing.
   type Signed_12 is range -2048 .. 2047;

   --  Calibration state (one device per instantiation; no heap) ------
   type Calibration is record
      T1                             : Unsigned_16 := 0;
      T2, T3                         : Integer_16  := 0;
      P1                             : Unsigned_16 := 0;
      P2, P3, P4, P5, P6, P7, P8, P9 : Integer_16  := 0;
      H1                             : Unsigned_8  := 0;
      H2                             : Integer_16  := 0;
      H3                             : Unsigned_8  := 0;
      H4, H5                         : Signed_12   := 0;
      H6                             : Integer_8   := 0;
   end record;

   Cal         : Calibration;
   Initialized : Boolean := False;
   Osrs_T      : Byte := 2#010#;             --  X2
   Osrs_P      : Byte := 2#101#;             --  X16
   Osrs_H      : Byte := 2#001#;             --  X1
   Last_Acc    : Regmap.Access_Status := Regmap.Ok;

   function Last_Access_Status return Machine.Regmap.Access_Status
   is (Last_Acc);

   --  Helpers --------------------------------------------------------
   function To_I16 is new Ada.Unchecked_Conversion (Unsigned_16, Integer_16);
   function To_I8  is new Ada.Unchecked_Conversion (Unsigned_8, Integer_8);
   function To_I64 is new Ada.Unchecked_Conversion (Unsigned_64, Integer_64);
   function To_U64 is new Ada.Unchecked_Conversion (Integer_64, Unsigned_64);

   --  Arithmetic shifts, mirroring the datasheet C code's ">>"/"<<".
   --  All compensation runs in 64 bits: the C reference relies on
   --  wrap-free 32-bit ranges for valid input; 64-bit yields identical
   --  values and keeps Ada's overflow checks quiet by construction.
   function ASR (V : Integer_64; N : Natural) return Integer_64 is
     (To_I64 (Shift_Right_Arithmetic (To_U64 (V), N)));
   function ASL (V : Integer_64; N : Natural) return Integer_64 is
     (To_I64 (Shift_Left (To_U64 (V), N)));

   function U16_LE (Lo, Hi : Byte) return Unsigned_16 is
     (Unsigned_16 (Lo) or Shift_Left (Unsigned_16 (Hi), 8));

   function Map (A : Regmap.Access_Status) return Device_Status is
     (case A is
         when Regmap.Ok          => Ok,
         when Regmap.Timed_Out   => Timed_Out,
         when Regmap.Bus_Fault
            | Regmap.Other_Error => Bus_Fault);

   procedure Fail (Status : in out Device_Status;
                   A      : Regmap.Access_Status) is
   begin
      Last_Acc := A;
      Status   := Map (A);
      Log_Event ((case Status is
                    when Timed_Out => Ev_Timed_Out,
                    when others    => Ev_Bus_Fault));
   end Fail;

   function Osrs_Code (O : Oversampling) return Byte is
     (case O is
         when Skipped => 2#000#, when X1 => 2#001#, when X2  => 2#010#,
         when X4      => 2#011#, when X8 => 2#100#, when X16 => 2#101#);

   function Clamp (V, Lo, Hi : Integer_64) return Integer_64 is
     (if V < Lo then Lo elsif V > Hi then Hi else V)
     with Pre  => Lo <= Hi,
          Post => Clamp'Result in Lo .. Hi;

   --  §6.6: 'Fixed_Value is not yet supported by GNATprove, so the raw
   --  hundredths/Pa counts are turned into fixed-point values through the
   --  ordinary Ada fixed * integer multiply instead (exact, no float).
   --  'Base, not the subtype: Hectopascal's own range (300.00 .. 1100.00)
   --  does not include the 0.01 unit value itself.
   One_Cent : constant Celsius'Base     := 0.01;
   One_Pa   : constant Hectopascal'Base := 0.01;
   One_RH   : constant Percent_RH'Base  := 0.01;

   --  Operations -----------------------------------------------------

   procedure Initialize (Status : in out Device_Status) is
      A          : Regmap.Access_Status := Regmap.Ok;
      Id         : Byte_Array (1 .. 1);
      TP         : Byte_Array (1 .. 24);      --  0x88 .. 0x9F
      H1B        : Byte_Array (1 .. 1);       --  0xA1
      HB         : Byte_Array (1 .. 7);       --  0xE1 .. 0xE7
      E4, E5, E6 : Unsigned_16;
      H4_Raw, H5_Raw : Integer_16;
   begin
      if Status /= Ok then
         return;                              --  chained
      end if;

      Regs.Read_Regs (Reg_Id, Id, A);
      if A /= Regmap.Ok then Fail (Status, A); return; end if;
      if Id (1) /= Chip_Id then
         Status := Wrong_Chip_Id;
         Log_Event (Ev_Wrong_Id, Log.Arg (Id (1)));
         return;
      end if;

      Regs.Write_Reg (Reg_Reset, Reset_Command, A);
      if A /= Regmap.Ok then Fail (Status, A); return; end if;
      Wait.Delay_Ms (3);                      --  t_startup(max) = 2 ms

      Regs.Read_Regs (Reg_Calib_00, TP, A);
      Regs.Read_Regs (Reg_Calib_H1, H1B, A);
      Regs.Read_Regs (Reg_Calib_26, HB, A);
      if A /= Regmap.Ok then Fail (Status, A); return; end if;

      Cal.T1 := U16_LE (TP (1), TP (2));
      Cal.T2 := To_I16 (U16_LE (TP (3), TP (4)));
      Cal.T3 := To_I16 (U16_LE (TP (5), TP (6)));
      Cal.P1 := U16_LE (TP (7), TP (8));
      Cal.P2 := To_I16 (U16_LE (TP (9),  TP (10)));
      Cal.P3 := To_I16 (U16_LE (TP (11), TP (12)));
      Cal.P4 := To_I16 (U16_LE (TP (13), TP (14)));
      Cal.P5 := To_I16 (U16_LE (TP (15), TP (16)));
      Cal.P6 := To_I16 (U16_LE (TP (17), TP (18)));
      Cal.P7 := To_I16 (U16_LE (TP (19), TP (20)));
      Cal.P8 := To_I16 (U16_LE (TP (21), TP (22)));
      Cal.P9 := To_I16 (U16_LE (TP (23), TP (24)));

      Cal.H1 := Unsigned_8 (H1B (1));
      Cal.H2 := To_I16 (U16_LE (HB (1), HB (2)));
      Cal.H3 := Unsigned_8 (HB (3));
      --  H4: 0xE4[11:4] | 0xE5[3:0];  H5: 0xE6[11:4] | 0xE5[7:4].
      --  Both signed 12-bit.
      E4 := Unsigned_16 (HB (4));
      E5 := Unsigned_16 (HB (5));
      E6 := Unsigned_16 (HB (6));
      H4_Raw := To_I16 (Shift_Left (E4, 4) or (E5 and 16#0F#));
      H5_Raw := To_I16 (Shift_Left (E6, 4) or Shift_Right (E5, 4));
      if H4_Raw > 2047 then H4_Raw := H4_Raw - 4096; end if;
      if H5_Raw > 2047 then H5_Raw := H5_Raw - 4096; end if;
      Cal.H4 := Signed_12 (H4_Raw);
      Cal.H5 := Signed_12 (H5_Raw);
      Cal.H6 := To_I8 (Unsigned_8 (HB (7)));

      Initialized := True;
   end Initialize;

   procedure Configure
     (Temperature_Oversampling : Oversampling := X2;
      Pressure_Oversampling    : Oversampling := X16;
      Humidity_Oversampling    : Oversampling := X1;
      Status                   : in out Device_Status)
   is
      A : Regmap.Access_Status := Regmap.Ok;
   begin
      if Status /= Ok then
         return;                              --  chained
      end if;
      if not Initialized then
         Status := Not_Initialized;
         return;
      end if;
      Osrs_T := Osrs_Code (Temperature_Oversampling);
      Osrs_P := Osrs_Code (Pressure_Oversampling);
      Osrs_H := Osrs_Code (Humidity_Oversampling);
      --  ctrl_hum takes effect on the next ctrl_meas write (datasheet);
      --  mode stays "sleep" here, Measure triggers forced conversions.
      Regs.Write_Reg (Reg_Ctrl_Hum, Osrs_H, A);
      Regs.Write_Reg (Reg_Ctrl_Meas, Osrs_T * 2**5 or Osrs_P * 2**2, A);
      if A /= Regmap.Ok then Fail (Status, A); end if;
   end Configure;

   procedure Measure (Result : out Measurement;
                      Status : in out Device_Status)
   is
      A    : Regmap.Access_Status := Regmap.Ok;
      St   : Byte_Array (1 .. 1);
      D    : Byte_Array (1 .. 8);              --  0xF7 .. 0xFE
      Poll : Natural := 0;

      Adc_P, Adc_T, Adc_H : Integer_64;

      V1, V2, T_Fine, T_Cents : Integer_64;
      P1, P2, P               : Integer_64;
      VX, VH                  : Integer_64;
      H_T1, H_Inner, H_T2     : Integer_64;

      P_Pa   : Integer_64;                     --  1 Pa = 0.01 hPa
      H_Cent : Integer_64;                     --  0.01 %RH units
   begin
      Result := (Temperature => 0.0,
                 Pressure    => 1000.0,
                 Humidity    => 0.0);
      if Status /= Ok then
         return;                               --  chained
      end if;
      if not Initialized then
         Status := Not_Initialized;
         return;
      end if;

      --  Trigger one forced-mode conversion.
      Regs.Write_Reg (Reg_Ctrl_Hum, Osrs_H, A);
      Regs.Write_Reg (Reg_Ctrl_Meas,
                      Osrs_T * 2**5 or Osrs_P * 2**2 or Mode_Forced, A);
      if A /= Regmap.Ok then Fail (Status, A); return; end if;

      --  Wait for completion: poll status.measuring (bit 3).
      loop
         pragma Loop_Invariant (Poll <= 60);
         Wait.Delay_Ms (2);
         Regs.Read_Regs (Reg_Status, St, A);
         if A /= Regmap.Ok then Fail (Status, A); return; end if;
         exit when (St (1) and 2#0000_1000#) = 0;
         Poll := Poll + 1;
         if Poll > 60 then                     --  >> max conversion time
            Status := Timed_Out;
            Log_Event (Ev_Timed_Out);
            return;
         end if;
      end loop;

      Regs.Read_Regs (Reg_Data, D, A);
      if A /= Regmap.Ok then Fail (Status, A); return; end if;

      Adc_P := Integer_64 (D (1)) * 2**12 + Integer_64 (D (2)) * 2**4
                 + Integer_64 (D (3)) / 2**4;
      Adc_T := Integer_64 (D (4)) * 2**12 + Integer_64 (D (5)) * 2**4
                 + Integer_64 (D (6)) / 2**4;
      Adc_H := Integer_64 (D (7)) * 2**8 + Integer_64 (D (8));

      --  Temperature (datasheet 4.2.3), result in 0.01 degC ----------
      V1 := ASR ((ASR (Adc_T, 3) - Integer_64 (Cal.T1) * 2)
                 * Integer_64 (Cal.T2), 11);
      V2 := ASR (ASR ((ASR (Adc_T, 4) - Integer_64 (Cal.T1))
                      * (ASR (Adc_T, 4) - Integer_64 (Cal.T1)), 12)
                 * Integer_64 (Cal.T3), 14);
      T_Fine  := V1 + V2;
      T_Cents := ASR (T_Fine * 5 + 128, 8);

      --  Pressure (64-bit variant), intermediate Q24.8 Pa ------------
      P1 := T_Fine - 128_000;
      P2 := P1 * P1 * Integer_64 (Cal.P6);
      P2 := P2 + ASL (P1 * Integer_64 (Cal.P5), 17);
      P2 := P2 + ASL (Integer_64 (Cal.P4), 35);
      P1 := ASR (P1 * P1 * Integer_64 (Cal.P3), 8)
              + ASL (P1 * Integer_64 (Cal.P2), 12);
      P1 := ASR ((ASL (1, 47) + P1) * Integer_64 (Cal.P1), 33);
      --  A near-zero P1 (not just exactly zero) drives the division below
      --  into an arbitrarily large quotient -- a real sensor's P1 sits in
      --  the hundreds of millions (~6*10**8 for the datasheet's own
      --  reference vector); anything under this floor cannot come from a
      --  working device and is rejected the same way an exact zero is.
      if abs (P1) < 1_000_000 then
         P_Pa := 30_000;                       --  avoid division by zero
      else
         P := 1_048_576 - Adc_P;
         P := ((ASL (P, 31) - P2) * 3_125) / P1;
         P1 := ASR (Integer_64 (Cal.P9) * ASR (P, 13) * ASR (P, 13), 25);
         P2 := ASR (Integer_64 (Cal.P8) * P, 19);
         P := ASR (P + P1 + P2, 8) + ASL (Integer_64 (Cal.P7), 4);
         P_Pa := ASR (P, 8);                   --  Q24.8 -> Pa
      end if;

      --  Humidity (datasheet 4.2.3, Bosch bme280_compensate_H_int32).
      --  v_x1_new = Term1 * Term2, where Term2 already carries its own
      --  "* H2 + 8192, >> 14" — that shift must land on Term2 alone,
      --  *before* the multiplication by Term1. (An earlier draft folded
      --  the two statements so the final >>14 applied to the product
      --  Term1*(...) instead, which is not the same value under integer
      --  division; fixed here by keeping Term1/Term2 as separate terms.)
      VX      := T_Fine - 76_800;
      H_T1    := ASR (ASL (Adc_H, 14) - ASL (Integer_64 (Cal.H4), 20)
                      - Integer_64 (Cal.H5) * VX + 16_384, 15);
      H_Inner := ASR (ASR (VX * Integer_64 (Cal.H6), 10)
                      * (ASR (VX * Integer_64 (Cal.H3), 11) + 32_768), 10);
      H_T2    := ASR ((H_Inner + 2_097_152) * Integer_64 (Cal.H2) + 8_192, 14);
      VH      := H_T1 * H_T2;
      VH := VH - ASR (ASR (ASR (VH, 15) * ASR (VH, 15), 7)
                      * Integer_64 (Cal.H1), 4);
      VH := Clamp (VH, 0, 419_430_400);

      --  Convert to the fixed-point result types (clamped to range).
      T_Cents := Clamp (T_Cents, -4_000, 8_500);
      P_Pa    := Clamp (P_Pa, 30_000, 110_000);
      H_Cent  := Clamp ((ASR (VH, 12) * 100 + 512) / 1_024, 0, 10_000);

      Result.Temperature := Celsius     (One_Cent * Integer (T_Cents));
      Result.Pressure    := Hectopascal (One_Pa   * Integer (P_Pa));
      Result.Humidity    := Percent_RH  (One_RH   * Integer (H_Cent));
   end Measure;

end BME280;
