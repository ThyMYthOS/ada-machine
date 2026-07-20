with Ada.Synchronous_Task_Control;
with Machine.SPI;

use type Machine.SPI.Transaction_Status;

package body Machine.Tasking.Generic_SPI
  with SPARK_Mode
is

   --  Handoff state between ISR context (Signal, called from
   --  Async_Core.On_Interrupt) and the suspended caller (Exchange).
   --  Volatile: the same "touched from both mainline and interrupt
   --  context" reasoning as machine_async's own TX_Buf/RX_Buf/Result, and
   --  as ATmega328P.SPI's Busy -- the Suspension_Object's Set_True/
   --  Suspend_Until_True pair is the synchronization point that makes
   --  the plain-variable read on the other side safe.
   Done        : Ada.Synchronous_Task_Control.Suspension_Object;
   Last_Count  : Natural := 0 with Volatile;
   Last_Status : Machine.SPI.Transaction_Status := Machine.SPI.Ok
     with Volatile;

   procedure Signal (Transferred : Natural;
                     Status      : Machine.SPI.Transaction_Status) is
   begin
      Last_Count  := Transferred;
      Last_Status := Status;
      Ada.Synchronous_Task_Control.Set_True (Done);
   end Signal;

   package Async_Core is new Machine.Async.SPI
     (Port => Port, Buffer_Size => Buffer_Size, On_Complete => Signal);

   procedure On_Interrupt is
   begin
      Async_Core.On_Interrupt;
   end On_Interrupt;

   procedure Exchange (TX         : Byte_Array;
                       RX         : out Byte_Array;
                       Timeout_Ms : Natural;
                       Status     : in out Machine.SPI.Transaction_Status)
   is
      pragma Unreferenced (Timeout_Ms);  --  see spec: not enforced here
      Last : Natural;
   begin
      RX := (others => 0);
      if Status /= Machine.SPI.Ok then
         return;                          --  chained: skip if pending
      end if;
      Async_Core.Start_Exchange (TX, Status);
      if Status /= Machine.SPI.Ok then
         return;
      end if;
      Ada.Synchronous_Task_Control.Suspend_Until_True (Done);
      Status := Last_Status;
      if Status = Machine.SPI.Ok then
         Async_Core.Read_Response (RX, Last);
      end if;
   end Exchange;

end Machine.Tasking.Generic_SPI;
