with Ada.Synchronous_Task_Control;
with Machine.SPI;
with Machine.Generic_Critical_Section;

use type Machine.SPI.Transaction_Status;

package body Machine.Tasking.Generic_SPI
  with SPARK_Mode
is

   --  §14.4 critical section, instantiated as a no-op here -- this is
   --  NOT a claim that Async_Core's mainline/ISR races don't apply on
   --  this path (they do, the same shape as machine_async's own). It is
   --  a claim about *where* the real mutual exclusion comes from on the
   --  tasking path: under Ravenscar/Jorvik, pragma Attach_Handler only
   --  targets a protected procedure, so whatever attaches
   --  Async_Core.On_Interrupt to the real vector is necessarily a
   --  protected object already paying for priority-ceiling locking; a
   --  board that also routes its calls into Exchange (hence into
   --  Async_Core.Start_Exchange/Read_Response) through an operation of
   --  that SAME protected object gets real atomicity for free, exactly
   --  as Signal/Done's Suspension_Object already defers the completion
   --  *signal* to Ada.Synchronous_Task_Control instead of reinventing it
   --  in Machine.Async.SPI's own state. Nothing here enforces that a
   --  board actually does so -- same "the application's responsibility"
   --  shape as On_Interrupt's own attachment (D5) -- but a no-op Critical
   --  avoids this generic paying for (and this file reasoning about) a
   --  second, redundant locking layer stacked on top of Ravenscar's own.
   function  Null_Enter return Boolean is (False);
   procedure Null_Leave (Prev : Boolean) is null;
   package No_Critical is new Machine.Generic_Critical_Section
     (Mask_State => Boolean, Enter => Null_Enter, Leave => Null_Leave);

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
     (Port => Port, Buffer_Size => Buffer_Size, On_Complete => Signal,
      Critical => No_Critical);

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
