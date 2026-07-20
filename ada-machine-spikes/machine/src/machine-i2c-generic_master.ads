--  The never-blocking L2 data phase: command/data FIFO primitives,
--  chained on Bus_Status. A FIFO-less controller (AVR TWI) presents
--  itself as a depth-1 FIFO.
generic
   with procedure Set_Target (Address : Address_7_Bit);
                                          --  select the addressed device
   with function  Can_Push return Boolean;
                                          --  True when the command FIFO has room
   with procedure Push_Write (Data : Byte; Stop : Boolean;
                              Status : in out Bus_Status);
                                          --  enqueue a write byte (+ STOP flag)
   with procedure Push_Read_Request (Stop : Boolean;
                                     Status : in out Bus_Status);
                                          --  enqueue a read slot (+ STOP flag)
   with function  Can_Pop return Boolean;
                                          --  True when received data is available
   with procedure Pop (Data : out Byte; Status : in out Bus_Status);
                                          --  dequeue one received byte
package Machine.I2C.Generic_Master
  with Pure, SPARK_Mode
is end Machine.I2C.Generic_Master;
