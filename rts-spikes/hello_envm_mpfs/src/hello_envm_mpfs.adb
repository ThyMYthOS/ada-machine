--  Proves RTS-PRODUCTION.md §A6's XIP .data copy: this application is
--  built at Memory_Profile => envm (place-envm.ld), so .text/.rodata
--  execute in place from eNVM while .data has LMA (envm) != VMA
--  (l2lim). XIP_Marker.Text prints correctly only if start-ram.S's
--  copy loop actually ran before this Put_Line reads it.
with Ada.Text_IO;
with XIP_Marker;

procedure Hello_Envm_MPFS is
begin
   Ada.Text_IO.Put_Line (XIP_Marker.Text);

   --  A bare-metal image must not return from its main subprogram.
   loop
      null;
   end loop;
end Hello_Envm_MPFS;
