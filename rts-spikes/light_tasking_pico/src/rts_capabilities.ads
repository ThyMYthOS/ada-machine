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
--  RP2040 is a Cortex-M0+ with no FPU, so neither precision has a
--  hardware square root and both patched bodies take their software
--  path.
--
--  NOT derived from Device, deliberately -- and RP2350 is why. Measured
--  from the published light_tasking_rp2350 crate: cortex-m33,
--  mfloat-abi=hard. Its FPU is single-precision, so an rp2350 leaf wants
--
--     Has_Hw_Sqrt_Single : constant Boolean := True;
--     Has_Hw_Sqrt_Double : constant Boolean := False;
--
--  That split is exactly what a per-capability directory pair could not
--  express and what moving the choice into the body bought us. Deriving
--  both from one "has an FPU" flag would get the double case wrong.

package RTS_Capabilities is
   pragma Pure;

   Has_Hw_Sqrt_Single : constant Boolean := False;
   Has_Hw_Sqrt_Double : constant Boolean := False;

end RTS_Capabilities;
