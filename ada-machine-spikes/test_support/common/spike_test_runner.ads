--  Spike_Test_Runner -- test-mode body shared by the BME280 spikes
--  (TODO.md #15 Step 2): initialise the sensor, run Cycles measurement
--  cycles, judge each, write one fixed ASCII verdict line to the UART and
--  halt, so a simulator harness gets an unambiguous end-of-run signal.
--
--  Verdict line (CR LF terminated, written directly through the L2 UART
--  port -- an application-level convenience allowed by README 14.2, the
--  libraries still only emit Event_Id + Arg records):
--
--    ADA-MACHINE-TEST: PASS
--    ADA-MACHINE-TEST: FAIL <reason-code>
--
--  reason-code (one token, upper case):
--    INIT-<S>     Initialize/Configure ended with Device_Status <S>
--    MEASURE-<S>  a Measure cycle ended with Device_Status <S>
--    RANGE-TEMP | RANGE-PRESS | RANGE-HUM   value outside the BME280
--                 datasheet operating range
--  with <S> one of OK WRONG_CHIP_ID BUS_FAULT TIMED_OUT NOT_INITIALIZED.
--
--  Each good cycle also reports the temperature through On_Measured (the
--  application wires that to its Ev_Measured log event), so the binary
--  event stream precedes the verdict. tools/decode_log.py reads both.
with BME280;
with Machine.Log;
with Machine.UART.Generic_Port;
generic
   with package Sensor is new BME280 (<>);
                                    --  the board's driver instance
   with package UART is new Machine.UART.Generic_Port (<>);
                                    --  the L2 port the verdict is written to
   with procedure Delay_Ms (Ms : Natural);
                                    --  bounded delay, used to let the TX
                                    --  FIFO drain (no L2 "TX empty" query)
   with procedure Halt;             --  never returns (Spike_Halt.Halt)
   with procedure On_Measured (Temperature_Centi : Machine.Log.Arg);
                                    --  temperature in 1/100 degC, two's
                                    --  complement in 32 bits when negative
package Spike_Test_Runner
  with SPARK_Mode
is
   Cycles   : constant := 3;
   --  The deepest TX FIFO here (ESP32-C3: 128 bytes at 115200 baud, about
   --  11 ms) bounds the data still in flight when the last byte is queued
   --  (Put blocks while the FIFO is full); 20 ms covers it.
   Drain_Ms : constant := 20;

   procedure Run;               --  cycles, verdict, drain; returns
   procedure Run_And_Halt       --  Run, then Halt (the application entry)
     with No_Return;
end Spike_Test_Runner;
