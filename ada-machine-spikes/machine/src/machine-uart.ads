--  UART class vocabulary. Signatures live beneath as generic children.
package Machine.UART
  with Pure, SPARK_Mode
is
   --  L2 status: no Timed_Out -- L2 never waits. Named after the 16550's
   --  Line Status Register, per §6.3's domain-name rule.
   type Line_Status is (Ok, Framing_Error, Parity_Error, Overrun, Other_Error);

   --  Bounded-transaction outcome (blocking calls, async completion).
   type Transaction_Status is
     (Ok, Timed_Out, Framing_Error, Parity_Error, Overrun, Other_Error);

   --  Event plumbing for L3b (§6.2): L2 exposes Enable_Event/
   --  Disable_Event/Pending_Event/Clear_Event over these; unused by the
   --  blocking adapters in these spikes.
   type Event is (Tx_Ready, Rx_Ready, Error);
   type Event_Set is array (Event) of Boolean;

end Machine.UART;
