--  A package-level, NON-constant String. It must live in .data (an
--  initialised, mutable object -- not something GCC can fold into
--  .rodata the way a "constant" could be), so it is only correct at
--  run time if start-ram.S's copy loop moved it from its LMA (envm)
--  to its VMA (l2lim) before Hello_Envm_MPFS reads it.
package XIP_Marker is
   Text : String := "XIP DATA COPY OK";
end XIP_Marker;
