--  MPFS -- root package for the PolarFire SoC AMP system description
--  (RTS-POLARFIRE.md §4). Holds no declarations of its own; see the
--  child package MPFS.System_Map for the generated cross-partition
--  data. Kept as a separate, empty parent (rather than folding
--  everything into one unit) so a future generator run can add
--  sibling children -- e.g. a decoded PMP table (RTS-POLARFIRE.md §11
--  item 12) -- without disturbing System_Map's own name or contents.

package MPFS is

   pragma Pure (MPFS);
   pragma No_Elaboration_Code_All;

end MPFS;
