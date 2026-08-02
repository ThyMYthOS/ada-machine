--  Runtime capabilities under a name every leaf provides, so that a unit
--  SHARED between targets can select on them in its body
--  (rts_sources_gcc15/rts_sources_gcc15.gpr, Patched_Dir).
--
--  Must be Pure: System.Libm_Single.Squareroot is Pure and a pure unit
--  cannot depend on a non-pure one. Alire's generated configuration is
--  Pure, so withing it directly here is legal -- and this file is
--  per-leaf, so it may name that package by its real name. Only the
--  CONSUMER needs a stable name, which is why this package has one and
--  the config shim next door does not suffice.
--
--  DERIVED, never configured: bit 0 of the hart mask is the E51, which
--  has no FPU. Every other mask names U54s, which are rv64imafdc and
--  have both single- and double-precision hardware sqrt. Deriving keeps
--  this from disagreeing with the ISA switches target_options.gpr
--  computes from the same mask (CONTRACT.md 7.13). Equality on a static
--  integer is RM-static, so the `if` in the patched bodies folds in the
--  front end.

with Embedded_Mpfs_Config;

package RTS_Capabilities is
   pragma Pure;

   Has_Hw_Sqrt_Single : constant Boolean :=
     Embedded_Mpfs_Config.Harts_Mask /= 1;
   Has_Hw_Sqrt_Double : constant Boolean :=
     Embedded_Mpfs_Config.Harts_Mask /= 1;

end RTS_Capabilities;
