--  The never-blocking L2 data phase for I2C *target* (slave) mode --
--  the mirror image of Generic_Master (spike 1-3 only ever drove the
--  MCU as bus master; spike 4 is the first to put it on the other side
--  of the bus). Chained on the same Bus_Status as the master signature
--  (§7.2), but the primitives are event-driven around address match,
--  transfer direction, and STOP rather than FIFO push/pop of a
--  transaction the caller itself initiated -- a target never decides
--  when a transaction starts.
--
--  Own-address configuration (7-bit address to answer to, general-call
--  handling, ...) stays native config (D8), done once via each HAL's
--  own Enable, exactly as Generic_Master's Set_Target is a separate
--  native step from the signature's data-phase primitives.
generic
   with function  Is_Address_Matched return Boolean;
                                          --  a master has addressed us;
                                          --  clock is stretched until
                                          --  Ack_Address
   with function  Is_Read_From_Master return Boolean;
                                          --  direction of the matched
                                          --  transfer: True = master
                                          --  wants to read (we transmit),
                                          --  False = master is writing
                                          --  (we receive)
   with procedure Ack_Address;
                                          --  release the clock stretch
                                          --  and begin the phase; not
                                          --  chained (§7.1 carve-out for
                                          --  control-plane acks, same
                                          --  reasoning as abort/cleanup
                                          --  ops -- it doesn't touch data)
   with function  Can_Pop return Boolean;
                                          --  a byte from the master is
                                          --  available (write phase)
   with procedure Pop  (Data : out Byte; Status : in out Bus_Status);
                                          --  dequeue one byte the master wrote
   with function  Can_Push return Boolean;
                                          --  the master is waiting for
                                          --  the next byte (read phase)
   with procedure Push (Data : Byte; Status : in out Bus_Status);
                                          --  supply one byte for the
                                          --  master to read
   with function  Is_Stop return Boolean;
                                          --  STOP (or repeated START into
                                          --  a new address match) ended
                                          --  the transaction
   with procedure Clear_Stop;
                                          --  acknowledge Is_Stop; not
                                          --  chained, same reasoning as
                                          --  Ack_Address
package Machine.I2C.Generic_Target
  with Pure, SPARK_Mode
is end Machine.I2C.Generic_Target;
