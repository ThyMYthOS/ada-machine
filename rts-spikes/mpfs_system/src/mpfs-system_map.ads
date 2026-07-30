--  ===========================================================================
--  GENERATED FILE -- HAND-WRITTEN STAND-IN for this spike.
--
--  In the real design (RTS-POLARFIRE.md §4.3) this file is emitted by a fork
--  of Microchip's `mpfs_configuration_generator.py`, reading:
--    * the MSS Configurator XML  -- per board, e.g. the HSS repository's
--      boards/mpfs-icicle-kit/soc_fpga_design/xml/ICICLE_MSS_mss_cfg.xml
--    * the HSS payload YAML      -- tools/hss-payload-generator's config
--  See ../README.md for the full generator-fork rationale and real vendor
--  paths, and ../../RTS-POLARFIRE.md §4 generally.
--
--  Every value below that is a fact ABOUT THE VENDOR FILES -- window
--  base/size, hart ownership, console, privilege, the two input-hash
--  stamps -- would be generator OUTPUT in the real design. Hand-editing
--  such a file is exactly the "second source of truth" §4.3 rejects for
--  production use; it is acceptable only here, where the point is to
--  demonstrate the mechanism (the cross-partition static checks), not to
--  maintain a real system's data. Nothing in this file was decoded from
--  real register values -- the worked example below mirrors the sample
--  hart-entry-points/payloads snippet already quoted in RTS-POLARFIRE.md
--  §4.1, chosen so the privilege modes and hart ownership below are not
--  invented but copied from that quotation.
--  ===========================================================================

with Interfaces;

package MPFS.System_Map is

   pragma Pure (MPFS.System_Map);
   pragma No_Elaboration_Code_All;

   ---------------------------------------------------------------------------
   --  1. Vocabulary
   ---------------------------------------------------------------------------

   type Partition_Id is (Monitor, App_Smp, App_Single);
   --  The worked three-partition Icicle-Kit-like example (RTS-POLARFIRE.md
   --  §4.4): Monitor on the E51 (hart 0); App_Smp on U54 harts 1-2 (SMP);
   --  App_Single on U54 hart 3. Hart 4 is deliberately left unclaimed here,
   --  matching RTS-POLARFIRE.md §7's own remark that a fourth partition
   --  (e.g. Linux) could own it without anything here needing to change.

   type Hart_Mask is mod 2 ** 5;
   --  One bit per hart: bit 0 = E51 (hart 0), bits 1-4 = U54 harts 1-4
   --  (RTS-POLARFIRE.md §1.1). The modulus is a power of 2, so Ada gives
   --  this type the predefined bitwise "and"/"or"/"not" (RM 3.5.4) that the
   --  hart-collision check below needs.

   Hart_0 : constant Hart_Mask := 2 ** 0;  --  E51 monitor
   Hart_1 : constant Hart_Mask := 2 ** 1;  --  U54 #1
   Hart_2 : constant Hart_Mask := 2 ** 2;  --  U54 #2
   Hart_3 : constant Hart_Mask := 2 ** 3;  --  U54 #3
   Hart_4 : constant Hart_Mask := 2 ** 4;  --  U54 #4 (unclaimed in this example)

   type Privilege_Mode is (M_Mode, S_Mode);
   --  Boot privilege level (RTS-POLARFIRE.md §4.2) -- the HSS payload
   --  YAML's `priv-mode: PRV_M` / `PRV_S`.

   type Console_Id is (Mmuart0, Mmuart1, Mmuart2, Mmuart3, Mmuart4,
                        Ram_Fifo, No_Console);
   --  Parallels CONTRACT.md §3.2's `Console` leaf configuration variable
   --  domain. In derived mode (RTS-POLARFIRE.md §5) this is an output of
   --  this crate, not a leaf-authored input.

   type Address64 is new Interfaces.Unsigned_64;
   type Size64    is new Interfaces.Unsigned_64;
   --  64-bit, not 32: the 38-bit DDR aliases (RTS-POLARFIRE.md §1.2) start
   --  at 16#10_0000_0000# and 16#18_0000_0000#, which do not fit in 32
   --  bits. A generator that modelled addresses as Unsigned_32 would
   --  silently truncate those two regions the day a partition used them.

   type Memory_Window is record
      Base : Address64;
      Size : Size64;
   end record;
   --  A half-open byte range [Base, Base + Size). Size = 0 means "this
   --  window does not exist" -- the same zero-length idiom
   --  RTS-POLARFIRE.md §1.3/§1.4 already uses for absent DDR aliases and
   --  foreign-hart ITIM windows; it lets App_Smp and Monitor below share
   --  one `Partition_Info` shape with App_Single even though only
   --  App_Single has an IPC window.

   ---------------------------------------------------------------------------
   --  2. Hardware maxima (RTS-POLARFIRE.md §1.2), trimmed to only the
   --     regions this three-partition example actually uses -- Monitor in
   --     LIM, App_Smp/App_Single in cached DDR, App_Single's IPC window in
   --     non-cached DDR. A full generator would carry every region of
   --     §1.2 (ENVM, per-hart ITIM/DTIM, the two 38-bit DDR aliases); this
   --     stand-in omits the ones no partition below claims, rather than
   --     padding the worked example with data nothing here exercises.
   --     These are load-bearing, not decorative: §4.3 warns the MSS XML's
   --     own `mem_elements` is "designer intent, not hardware ground
   --     truth" -- so a generator (and this stand-in) must range-check
   --     every window against the SoC's real ceilings rather than trust
   --     the vendor file to be internally consistent.
   --
   --     One honest gap: RTS-POLARFIRE.md §1.2 lists the 38-bit DDR
   --     aliases' non-cached/WCB sizes as "board-dependent" -- there is no
   --     SoC-fixed ceiling for those two regions, so no partition using
   --     them could get a "does not exceed hardware maxima" check the way
   --     every region below does; that is a genuine limit, not an
   --     oversight (see the task report).
   ---------------------------------------------------------------------------

   L2_Lim_Base_Address         : constant := 16#0800_0000#;
   L2_Lim_Max_Size             : constant := 15 * 128 * 1_024;   --  15 ways * 128 KB
   L2_Scratchpad_Base_Address  : constant := 16#0A00_0000#;
   L2_Scratchpad_Max_Size      : constant := 15 * 128 * 1_024;   --  same 15-way pool as LIM

   Ddr_Cached_Base_Address     : constant := 16#8000_0000#;
   Ddr_Cached_Max_Size         : constant := 1_024 * 1_024 * 1_024;  --  1 GB
   Ddr_Non_Cached_Base_Address : constant := 16#C000_0000#;
   Ddr_Non_Cached_Max_Size     : constant := 256 * 1_024 * 1_024;

   ---------------------------------------------------------------------------
   --  3. The worked example, as FLAT named constants.
   --
   --  Why flat constants, and not `Partitions (P).Window.Base` style
   --  component selection into the array-of-records below (§5): verified
   --  directly against gnat_native 16.1.0 (see the task report) that a
   --  `pragma Compile_Time_Error` condition built from indexing into, or
   --  selecting a component of, a record/array-typed constant is simply
   --  NOT a static expression in Ada (RM 4.9 -- "static expression" only
   --  ever covers literals, named numbers, and constants of a *scalar or
   --  string* nominal subtype, never a `selected_component`/
   --  `indexed_component` of a composite object, regardless of what the
   --  component's own type is). GNAT does not diagnose the mistake
   --  either: such a pragma simply never fires, silently, even when the
   --  condition is in fact True -- the worst possible failure mode for a
   --  crate whose entire value is that its checks fire. Ada 2022 "static
   --  expression functions" (`with Static`) do not rescue this: a call is
   --  only static if every actual parameter is itself already static, and
   --  `Partitions (Monitor)` is exactly the non-static expression in
   --  question. So every quantity that participates in a check below is
   --  first given its own top-level scalar name; §4 builds the nicer
   --  `Partitions` table purely for ordinary (non-static-context)
   --  consumption by a partition's own startup code.
   ---------------------------------------------------------------------------

   --  Monitor -- E51, hart 0, soft-float (no FPU, RTS-POLARFIRE.md §1.1),
   --  resident in LIM at its reset default (needs no L2 programming,
   --  §1.2.1/§6.4). 256 KB matches the vendor reference configuration
   --  quoted in RTS-POLARFIRE.md §1.3.
   Monitor_Harts     : constant Hart_Mask     := Hart_0;
   Monitor_Base      : constant               := L2_Lim_Base_Address;
   Monitor_Size      : constant               := 256 * 1_024;
   Monitor_Console   : constant Console_Id    := Mmuart0;
   Monitor_Privilege : constant Privilege_Mode := M_Mode;

   --  App_Smp -- U54 harts 1-2 (SMP), resident in cached DDR. Matches
   --  RTS-POLARFIRE.md §4.1's own quoted payload YAML:
   --  "app-smp.elf: {owner-hart: u54_1, secondary-harts: [u54_2],
   --  priv-mode: PRV_M}".
   App_Smp_Harts     : constant Hart_Mask     := Hart_1 or Hart_2;
   App_Smp_Base      : constant               := Ddr_Cached_Base_Address;
   App_Smp_Size      : constant               := 64 * 1_024 * 1_024;
   App_Smp_Console   : constant Console_Id    := Mmuart1;
   App_Smp_Privilege : constant Privilege_Mode := M_Mode;

   --  App_Single -- U54 hart 3, resident in cached DDR immediately after
   --  App_Smp's window, with an IPC window in NON-cached DDR (§4.4:
   --  "coherence is not free"). Matches RTS-POLARFIRE.md §4.1's
   --  "app-single.elf: {owner-hart: u54_3, priv-mode: PRV_S}".
   App_Single_Harts     : constant Hart_Mask     := Hart_3;
   App_Single_Base      : constant               := App_Smp_Base + App_Smp_Size;
   App_Single_Size      : constant               := 32 * 1_024 * 1_024;
   App_Single_Console   : constant Console_Id    := Mmuart2;
   App_Single_Privilege : constant Privilege_Mode := S_Mode;

   App_Single_Ipc_Base : constant := Ddr_Non_Cached_Base_Address;
   App_Single_Ipc_Size : constant := 1 * 1_024 * 1_024;

   --  Which partition owns the L2 way configuration (RTS-POLARFIRE.md
   --  §6.4). The L2 reset default is 15 ways of LIM + 1 way of cache
   --  (1920 KB), so Monitor -- LIM-resident -- needs no L2 programming to
   --  boot at all, which is exactly what makes it the natural owner of
   --  any *change* to the split: it can run first, from the unconfigured
   --  reset state, and reprogram the ways before releasing the U54s.
   L2_Configuration_Owner : constant Partition_Id := Monitor;

   --  NOTE -- a check this crate CANNOT express statically. §6.4 states
   --  the ordering rule in prose: "a partition placed in LIM and a
   --  partition that reduces LIM are in a startup-order relationship."
   --  L2_Configuration_Owner *records* who is responsible; nothing here
   --  can verify that partition actually ran first, because "ran before"
   --  is a property of one specific boot sequence across N independently
   --  linked binaries, observable at run time at the earliest -- never at
   --  any one partition's compile time. It remains a stated contract, not
   --  an enforced one (RTS-POLARFIRE.md §6.4, §11 item 10).

   ---------------------------------------------------------------------------
   --  4. Staleness mitigation (RTS-POLARFIRE.md §4.4): a hash of BOTH
   --     vendor inputs, stamped into the generated spec. A real generator
   --     run computes these from the actual MSS Configurator XML and HSS
   --     payload YAML bytes (e.g. a truncated SHA-256 of each file). This
   --     spike stand-in was not generated from real vendor files, so the
   --     values below are fixed, clearly-marked placeholders.
   --
   --     Each partition that depends on this crate is EXPECTED to assert
   --     its own compiled-in expectation against these two values, e.g.:
   --
   --       pragma Compile_Time_Error
   --         (MPFS.System_Map.Mss_Config_Xml_Hash /= Expected_Mss_Hash
   --            or else
   --          MPFS.System_Map.Hss_Payload_Yaml_Hash /= Expected_Hss_Hash,
   --          "partition built against a stale mpfs_system -- regenerate");
   --
   --     mpfs_system cannot perform that assertion itself: it has no
   --     visibility into what any partition's own build expects, and
   --     nothing stops a partition from omitting the check, or from not
   --     depending on this crate at all (RTS-POLARFIRE.md §11 item 7:
   --     "a convention Alire cannot enforce"). Verified separately (task
   --     report) that a cross-package reference to a String constant like
   --     this one is itself still a static expression, so the pattern
   --     above genuinely compiles as a `pragma Compile_Time_Error`.
   ---------------------------------------------------------------------------

   Mss_Config_Xml_Hash   : constant String := "STANDIN-MSS-0000000000000000";
   Hss_Payload_Yaml_Hash : constant String := "STANDIN-HSS-0000000000000000";

   ---------------------------------------------------------------------------
   --  5. The structured view. Ordinary (non-static-context) consumption
   --     only: a partition's own startup code reads e.g.
   --     `MPFS.System_Map.Partitions (Own_Partition).Window` at
   --     elaboration or run time to learn its own hart mask, console and
   --     privilege -- none of which requires RM-static-ness. See the note
   --     in §3 for why the cross-partition checks in §6 do not use this
   --     table.
   ---------------------------------------------------------------------------

   type Partition_Info is record
      Harts     : Hart_Mask;
      Window    : Memory_Window;
      IPC       : Memory_Window;  --  (0, 0) if the partition has no IPC window
      Console   : Console_Id;
      Privilege : Privilege_Mode;
   end record;

   type Partition_Table is array (Partition_Id) of Partition_Info;

   Partitions : constant Partition_Table :=
     (Monitor    => (Harts     => Monitor_Harts,
                     Window    => (Base => Monitor_Base, Size => Monitor_Size),
                     IPC       => (Base => 0, Size => 0),
                     Console   => Monitor_Console,
                     Privilege => Monitor_Privilege),
      App_Smp    => (Harts     => App_Smp_Harts,
                     Window    => (Base => App_Smp_Base, Size => App_Smp_Size),
                     IPC       => (Base => 0, Size => 0),
                     Console   => App_Smp_Console,
                     Privilege => App_Smp_Privilege),
      App_Single => (Harts     => App_Single_Harts,
                     Window    => (Base => App_Single_Base,
                                   Size => App_Single_Size),
                     IPC       => (Base => App_Single_Ipc_Base,
                                   Size => App_Single_Ipc_Size),
                     Console   => App_Single_Console,
                     Privilege => App_Single_Privilege));

   ---------------------------------------------------------------------------
   --  6. The cross-partition checks. Only this crate can make these,
   --     because only this crate sees every partition at once
   --     (RTS-POLARFIRE.md §4). `pragma Compile_Time_Error`, never a
   --     subtype: RTS.md A.15 measured that a violated constrained
   --     subtype or predicate is only a *warning*, and the build still
   --     succeeds -- exactly the silently-bricked-board failure mode
   --     this crate exists to close.
   ---------------------------------------------------------------------------

   -----------------------------------------------------------
   --  6.1 Window overlap between any two partitions
   -----------------------------------------------------------

   Monitor_App_Smp_Overlap : constant Boolean :=
     Monitor_Base < App_Smp_Base + App_Smp_Size
       and then App_Smp_Base < Monitor_Base + Monitor_Size;

   pragma Compile_Time_Error
     (Monitor_App_Smp_Overlap,
      "MPFS.System_Map: Monitor and App_Smp memory windows overlap");

   Monitor_App_Single_Overlap : constant Boolean :=
     Monitor_Base < App_Single_Base + App_Single_Size
       and then App_Single_Base < Monitor_Base + Monitor_Size;

   pragma Compile_Time_Error
     (Monitor_App_Single_Overlap,
      "MPFS.System_Map: Monitor and App_Single memory windows overlap");

   App_Smp_App_Single_Overlap : constant Boolean :=
     App_Smp_Base < App_Single_Base + App_Single_Size
       and then App_Single_Base < App_Smp_Base + App_Smp_Size;

   pragma Compile_Time_Error
     (App_Smp_App_Single_Overlap,
      "MPFS.System_Map: App_Smp and App_Single memory windows overlap");

   -----------------------------------------------------------
   --  6.2 Two partitions claiming the same hart
   -----------------------------------------------------------

   Monitor_App_Smp_Hart_Collision : constant Boolean :=
     (Monitor_Harts and App_Smp_Harts) /= 0;

   pragma Compile_Time_Error
     (Monitor_App_Smp_Hart_Collision,
      "MPFS.System_Map: Monitor and App_Smp both claim a hart");

   Monitor_App_Single_Hart_Collision : constant Boolean :=
     (Monitor_Harts and App_Single_Harts) /= 0;

   pragma Compile_Time_Error
     (Monitor_App_Single_Hart_Collision,
      "MPFS.System_Map: Monitor and App_Single both claim a hart");

   App_Smp_App_Single_Hart_Collision : constant Boolean :=
     (App_Smp_Harts and App_Single_Harts) /= 0;

   pragma Compile_Time_Error
     (App_Smp_App_Single_Hart_Collision,
      "MPFS.System_Map: App_Smp and App_Single both claim a hart");

   -----------------------------------------------------------
   --  6.3 Two partitions claiming the same MMUART. Ram_Fifo/No_Console
   --      are not physical peripherals, so equal values there are not a
   --      collision -- only a shared *real* MMUART instance is.
   -----------------------------------------------------------

   Monitor_App_Smp_Console_Collision : constant Boolean :=
     Monitor_Console = App_Smp_Console
       and then Monitor_Console in Mmuart0 .. Mmuart4;

   pragma Compile_Time_Error
     (Monitor_App_Smp_Console_Collision,
      "MPFS.System_Map: Monitor and App_Smp claim the same MMUART");

   Monitor_App_Single_Console_Collision : constant Boolean :=
     Monitor_Console = App_Single_Console
       and then Monitor_Console in Mmuart0 .. Mmuart4;

   pragma Compile_Time_Error
     (Monitor_App_Single_Console_Collision,
      "MPFS.System_Map: Monitor and App_Single claim the same MMUART");

   App_Smp_App_Single_Console_Collision : constant Boolean :=
     App_Smp_Console = App_Single_Console
       and then App_Smp_Console in Mmuart0 .. Mmuart4;

   pragma Compile_Time_Error
     (App_Smp_App_Single_Console_Collision,
      "MPFS.System_Map: App_Smp and App_Single claim the same MMUART");

   -----------------------------------------------------------
   --  6.4 A window exceeding the hardware maxima of §1.2
   -----------------------------------------------------------

   Monitor_Exceeds_Lim : constant Boolean :=
     Monitor_Base < L2_Lim_Base_Address
       or else Monitor_Base + Monitor_Size >
               L2_Lim_Base_Address + L2_Lim_Max_Size;

   pragma Compile_Time_Error
     (Monitor_Exceeds_Lim,
      "MPFS.System_Map: Monitor's window exceeds the L2 LIM hardware maximum");

   App_Smp_Exceeds_Ddr_Cached : constant Boolean :=
     App_Smp_Base < Ddr_Cached_Base_Address
       or else App_Smp_Base + App_Smp_Size >
               Ddr_Cached_Base_Address + Ddr_Cached_Max_Size;

   pragma Compile_Time_Error
     (App_Smp_Exceeds_Ddr_Cached,
      "MPFS.System_Map: App_Smp's window exceeds the cached-DDR hardware " &
      "maximum");

   App_Single_Exceeds_Ddr_Cached : constant Boolean :=
     App_Single_Base < Ddr_Cached_Base_Address
       or else App_Single_Base + App_Single_Size >
               Ddr_Cached_Base_Address + Ddr_Cached_Max_Size;

   pragma Compile_Time_Error
     (App_Single_Exceeds_Ddr_Cached,
      "MPFS.System_Map: App_Single's window exceeds the cached-DDR " &
      "hardware maximum");

   App_Single_Ipc_Exceeds_Ddr_Non_Cached : constant Boolean :=
     App_Single_Ipc_Base < Ddr_Non_Cached_Base_Address
       or else App_Single_Ipc_Base + App_Single_Ipc_Size >
               Ddr_Non_Cached_Base_Address + Ddr_Non_Cached_Max_Size;

   pragma Compile_Time_Error
     (App_Single_Ipc_Exceeds_Ddr_Non_Cached,
      "MPFS.System_Map: App_Single's IPC window exceeds the non-cached-DDR " &
      "hardware maximum");

   -----------------------------------------------------------
   --  6.5 An IPC window placed in a CACHED region (§4.4: "coherence is
   --      not free" -- the U54s are coherent through L2, but a LIM- or
   --      DDR-resident partition is not automatically coherent with a
   --      cached-DDR one). L2 LIM is explicitly NOT cached (§1.2.1), so
   --      only L2 scratchpad and the (32-bit) DDR cached alias count
   --      here -- the 38-bit DDR cached alias is out of scope for this
   --      trimmed worked example (§2).
   -----------------------------------------------------------

   App_Single_Ipc_In_Cached_Region : constant Boolean :=
     (App_Single_Ipc_Base in
        L2_Scratchpad_Base_Address ..
          L2_Scratchpad_Base_Address + L2_Scratchpad_Max_Size - 1)
     or else
     (App_Single_Ipc_Base in
        Ddr_Cached_Base_Address .. Ddr_Cached_Base_Address + Ddr_Cached_Max_Size - 1);

   pragma Compile_Time_Error
     (App_Single_Ipc_In_Cached_Region,
      "MPFS.System_Map: App_Single's IPC window is in a CACHED region -- " &
      "coherence is not free (RTS-POLARFIRE.md §4.4); place it in the " &
      "non-cached DDR alias");

end MPFS.System_Map;
