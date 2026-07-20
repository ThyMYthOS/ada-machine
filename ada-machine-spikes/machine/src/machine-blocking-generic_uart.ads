--  The blocking execution model's UART contract (§8.1): writes all
--  frames of Data or times out, chained (§7.1) on line kinds + Timed_Out.
with Machine.UART;
generic
   with procedure Put (Data       : Byte_Array;
                       Timeout_Ms : Natural;
                       Status     : in out Machine.UART.Transaction_Status);
package Machine.Blocking.Generic_UART
  with Pure, SPARK_Mode
is end Machine.Blocking.Generic_UART;
