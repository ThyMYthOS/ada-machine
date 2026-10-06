#!/usr/bin/env python3
"""Generate MPFS_MSS_Config from the MSS Configurator XML (RTS-PRODUCTION.md A7
Step 3).

    ./generate_mpfs_config.py [xml/<file>.xml] [config/mpfs_mss_config.ads]

With no argument, the XML file is `<MPFS_PAC_XML_DIR>/<XML_File>`.
`XML_File` is this crate's own Alire configuration variable (a bare
filename) -- read out of the gnat_config/*.gpr Alire itself generates,
not re-parsed from alire.toml. `MPFS_PAC_XML_DIR` is an environment
variable, **not** an Alire configuration variable: the example XML is
not vendored in this crate (it belongs to whichever leaf exercises MSS
bring-up against real hardware, e.g. tests/mpfs_mss_init_test/xml/),
and `XML_File` alone cannot name it. `XML_File`'s value is resolved
here, against *this* crate's own directory, never the consumer's, and
`${CRATE_ROOT}` is never expanded inside a `[configuration.values]`
string at all -- it is only ever substituted in a crate's own
`[environment]` entries (RTS-GUIDE.md §12 item 1). So a consumer that
wants `MPFS_MSS_Config` generated exports `MPFS_PAC_XML_DIR` from its own
`[environment]` (`MPFS_PAC_XML_DIR.set = "${CRATE_ROOT}/xml"`), where
`${CRATE_ROOT}` *does* expand to the consumer's own root, and that
variable is visible to this pre-build action regardless of which crate
the environment came from -- the same whole-solution environment that
makes `<CRATE>_ALIRE_PREFIX` visible everywhere (RTS-PRODUCTION.md
B1). `XML_File` itself stays a bare filename resolved against that
directory.

Both must be set together, or neither. A consumer with **neither**
`MPFS_PAC_XML_DIR` **nor** `XML_File` set (a `secondary`-role one,
needing only `MPFS_MSS.*` register access -- see this crate's own
alire.toml) is not an error: this script prints that it is skipping
and exits 0, generating no `MPFS_MSS_Config`. Setting only one of the two
*is* an error -- `XML_File` naming a file with no directory to look
in, or `MPFS_PAC_XML_DIR` naming a directory with no filename and no
default to guess one from.

Refuses an unknown xml_format_version (RTS-POLARFIRE.md risk 8), stamps a
sha256 of the XML into the output, and emits:

  - a Clocks package (CPU/AXI/APB/RTC/DDR/SGMII-ref Hz), derived from the
    XML's own <clocks> section rather than computed from PLL ratios here --
    the XML already carries Microchip's own computed result.
  - one Ada aggregate constant per *steady-state* register mpfs_mss_init
    writes once, matching the XML's own field names and values 1:1.

**What is deliberately NOT derived from the XML**, and why:

  - IOSCBCFG.TIMER, SYSREG.DFIAPB_CR, CFG_DDR_SGMII_PHY.DDRPHY_STARTUP,
    CFG_DDR_SGMII_PHY.DYN_CNTL, SCB_REGS.MSSIO_CONTROL_CR (its 4-step
    sequence), IOSCB_PLL_MSS/DDR.SOFT_RESET: these do not appear in the
    XML at all (DDRPHY_STARTUP, MSSIO_CONTROL_CR, TIMER, DFIAPB_CR) or
    appear with a value that is the device's *idle/final* state, not the
    *transient* value the boot sequence needs while bringing the PLL up
    (DYN_CNTL: the XML's own snapshot has every *_DYNEN bit at 0 -- dynamic
    APB access disabled again once bring-up is done -- while the sequence
    needs them at 1 *during* bring-up to reach the PLL registers at all).
    Measured directly: DYN_CNTL's XML value, taken at face value, would
    silently remove the APB access the rest of the sequence depends on.
    These stay as the fixed procedural constants Microchip's own reference
    sequence uses, unconditionally, regardless of board.
  - IOSCB_PLL_MSS.PLL_CTRL is written twice (staged powered-down, then
    powered up) -- a procedural two-step write, not two configurations.
    The *second* write is the steady state the XML describes; the first
    overrides only REG_POWERDOWN_B on top of it (Ada 2022 delta aggregate).
  - IOSCB_PLL_MSS.PLL_PHADJ is NOT derived at all. Its REG_OUT3_PHSINIT
    field is declared width="3" in the XML but carries value 0x8, which
    does not fit in 3 bits -- the overflow bit lands exactly on
    REG_LOADPHS_B's own bit position (offset 11+3=14, REG_LOADPHS_B is at
    14). This is precisely the "FIXME: XML says 0x8" the original
    reference sequence left on REG_LOADPHS_B, now narrowed down to an
    exact bit, not resolved: it's at least as plausible that the vendor
    XML mis-scoped a 4-bit window as 3-bit REG_OUT3_PHSINIT, as that
    REG_LOADPHS_B is meant to be set. Guessing either way bakes an
    unverified assumption into a PLL phase-adjust register. The generator
    refuses (see ada_aggregate's width check) and PLL_PHADJ stays the
    fixed value the original reference used, in mpfs_mss_init.adb.

**A register-name collision this generator resolves by section, not name
alone**: PLL_CTRL, PLL_REF_FB, PLL_DIV_0_1, PLL_DIV_2_3, PLL_CTRL2,
PLL_FRACN, SSCG_REG_0..3 and PLL_PHADJ are each declared *three times* in
this XML -- once under mss_pll, once under sgmii_pll, once under ddr_pll,
one register layout shared by three PLL instances. Looking these up by
name alone would nondeterministically pick whichever the XML happened to
list last. Every lookup here is (section path, register name).

**MSSIO_BANK{2,4}_IO_CFG_*_CR is a second special case.** The XML
represents each pin's 15-bit configuration as one packed value
(field name "IO_CFG_0"/"IO_CFG_1"), not as the individually-named
booleans our generated PAC exposes (RPC_IO_CFG_<pin>_IBUFMD_0 etc.,
svd2ada's own flattening of the pair-register -- see mpfs_pac's
fix_mistyped_registers.py docs for why this crate's generation differs
from the packed form). This script decodes that 15-bit value using the
same bit layout the PAC's own representation clause uses, verified
against mpfs_mss-sysreg.ads directly, not re-derived by assumption.
"""
import hashlib
import os
import re
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
#  config/, not gnat_config/: that name is the runtime leaves' own
#  convention (RTS-GUIDE.md §5.1), not this crate's -- Alire's default
#  config/ is what every other app crate here already uses, and it is
#  also where this script's own output (mpfs_mss_config.ads) lands, below.
GENERATED_CONFIG_GPR = os.path.join(HERE, "config", "mpfs_pac_config.gpr")


def configured_xml_file():
    """Read XML_File's configured value out of the GPR config Alire already
    generates before running a pre-build action (empirically confirmed: the
    file exists -- with this crate's [configuration.variables] baked in --
    the moment a pre-build action's command starts running, not just by the
    time the build finishes). Returns None if XML_File was never set --
    no consumer override, and this crate's alire.toml gives it no default
    -- distinct from it naming an actual filename."""
    try:
        with open(GENERATED_CONFIG_GPR) as f:
            text = f.read()
    except FileNotFoundError:
        return None
    m = re.search(r'XML_File\s*:=\s*"([^"]*)"', text)
    return m.group(1) if m and m.group(1) else None


#  This crate vendors no XML of its own (see the module docstring): a
#  consumer that wants MPFS_MSS_Config generated sets MPFS_PAC_XML_DIR, an
#  absolute path expanded from its own ${CRATE_ROOT} in its own
#  [environment]. Neither it nor XML_File set is not an error -- that is
#  the `secondary`-role consumer, which has no use for MPFS_MSS_Config. Only
#  one of the two set is an error -- there is no fallback for either.
if len(sys.argv) > 1:
    XML_PATH = sys.argv[1]
else:
    XML_DIR = os.environ.get("MPFS_PAC_XML_DIR")
    XML_FILE = configured_xml_file()
    if not XML_DIR and not XML_FILE:
        print("generate_mpfs_config.py: MPFS_PAC_XML_DIR and XML_File are "
              "both unset -- skipping, no MPFS_MSS_Config package generated")
        sys.exit(0)
    if not XML_DIR:
        sys.exit(f"error: mpfs_pac.XML_File is set to {XML_FILE!r} but "
                  f"MPFS_PAC_XML_DIR is not -- a filename with no directory "
                  f"to look in. Whatever depends on this crate must set "
                  f"[environment] MPFS_PAC_XML_DIR.set = "
                  f"\"${{CRATE_ROOT}}/xml\" (or wherever its XML lives) -- "
                  f"see this script's module docstring")
    if not XML_FILE:
        sys.exit(f"error: MPFS_PAC_XML_DIR is set to {XML_DIR!r} but "
                  f"mpfs_pac.XML_File is not -- a directory with no filename "
                  f"to look for and no default to guess one from. Whatever "
                  f"depends on this crate must also set "
                  f"[configuration.values] mpfs_pac.XML_File = \"....xml\" "
                  f"-- see this script's module docstring")
    XML_PATH = os.path.join(XML_DIR, XML_FILE)
OUT_PATH = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "config", "mpfs_mss_config.ads")

SUPPORTED_XML_FORMAT_VERSIONS = {"0.6.5"}

# -- Load and validate -------------------------------------------------

xml_bytes = open(XML_PATH, "rb").read()
xml_hash = hashlib.sha256(xml_bytes).hexdigest()
root = ET.fromstring(xml_bytes)

fmt_version = root.findtext(".//xml_format_version")
if fmt_version not in SUPPORTED_XML_FORMAT_VERSIONS:
    sys.exit(f"error: unsupported xml_format_version {fmt_version!r} in {XML_PATH}; "
             f"supported: {sorted(SUPPORTED_XML_FORMAT_VERSIONS)} "
             f"(RTS-POLARFIRE.md risk 8 -- refuse rather than guess)")

design_name = root.findtext(".//design_information/design_name") or "?"
part_no = root.findtext(".//design_information/mpfs_part_no") or "?"

parents = {c: p for p in root.iter() for c in p}


def section_path(reg):
    e, path = reg, []
    while e in parents:
        e = parents[e]
        path.append(e.tag)
    return "/".join(reversed(path))


# index: (section, register_name) -> [(field_name, value_int, width, rw, offset)]
registers = {}
for reg in root.iter("register"):
    key = (section_path(reg), reg.get("name"))
    fields = []
    for f in reg:
        if f.tag != "field":
            continue
        name = f.get("name")
        width = int(f.get("width"))
        offset = int(f.get("offset"))
        rw = f.get("Type") == "RW"
        text = (f.text or "").strip()
        try:
            value = int(text, 16) if text.lower().startswith("0x") else int(text or "0")
        except ValueError:
            value = 0
        fields.append((name, value, width, rw, offset))
    registers.setdefault(key, []).append(fields)

for key, occurrences in registers.items():
    if len(occurrences) > 1:
        sys.exit(f"error: register {key!r} appears {len(occurrences)} times "
                  f"under the same section path -- this generator assumes "
                  f"(section, name) is unique and that assumption just broke")
registers = {k: v[0] for k, v in registers.items()}


def reg_fields(section, name):
    key = (section, name)
    if key not in registers:
        sys.exit(f"error: register {name!r} not found under {section!r}")
    return registers[key]


def ada_aggregate(section, name, skip=()):
    """RW fields only, RESERVED*/skip-listed fields dropped, 1-bit fields
    as Boolean, wider fields as hex -- matching svd2ada's own convention
    for how mpfs_pac typed each field (verified throughout this crate's
    own development, not assumed here). Refuses a field whose XML value
    does not fit its own declared width rather than truncate or guess:
    measured once, in PLL_PHADJ.REG_OUT3_PHSINIT (declared width 3, value
    0x8), where the overflow bit lands exactly on the next field's own
    bit position (REG_LOADPHS_B) -- silently masking it would have
    picked an arbitrary answer to a real ambiguity in the vendor data."""
    lines = []
    for fname, value, width, rw, _off in reg_fields(section, name):
        if not rw or fname.upper().startswith("RESERVE") or fname in skip:
            continue
        if value >= (1 << width):
            sys.exit(f"error: {section}/{name}.{fname}: value {value:#x} does "
                      f"not fit its declared width {width} (max {(1 << width) - 1:#x}) "
                      f"-- refusing to truncate; this needs a human to resolve "
                      f"against the real register layout, not a guess")
        lines.append(f"{fname} => {'True' if value else 'False'}" if width == 1
                      else f"{fname} => 16#{value:X}#")
    lines.append("others => <>")
    return lines


# Bit layout of one packed MSSIO_BANK{2,4}_IO_CFG pin value, verified
# against mpfs_pac/src/mpfs_mss-sysreg.ads's own representation clause for
# MSSIO_BANK4_IO_CFG_0_1_CR_Register (RPC_IO_CFG_0_* at bits 0..14).
IO_CFG_BITS = [
    ("IBUFMD_0", 0), ("IBUFMD_1", 1), ("IBUFMD_2", 2),
    ("DRV_0", 3), ("DRV_1", 4), ("DRV_2", 5), ("DRV_3", 6),
    ("CLAMP", 7), ("ENHYST", 8), ("LOCKDN_EN", 9), ("WPD", 10),
    ("WPU", 11), ("ATP_EN", 12), ("LP_PERSIST_EN", 13), ("LP_BYPASS_EN", 14),
]


def ada_io_cfg_pair(section, name, pin_lo, pin_hi):
    """Decode IO_CFG_<pin>'s packed value into the flattened
    RPC_IO_CFG_<pin>_<suffix> fields our PAC actually declares. The field
    is named IO_CFG_<pin> (not a fixed IO_CFG_0/IO_CFG_1), e.g.
    MSSIO_BANK4_IO_CFG_2_3_CR has fields IO_CFG_2 and IO_CFG_3."""
    fields = {f[0]: f[1] for f in reg_fields(section, name) if f[3]}  # name -> value, RW only
    lines = []
    for pin, raw in ((pin_lo, fields[f"IO_CFG_{pin_lo}"]), (pin_hi, fields[f"IO_CFG_{pin_hi}"])):
        for suffix, bit in IO_CFG_BITS:
            lines.append(f"RPC_IO_CFG_{pin}_{suffix} => "
                          f"{'True' if (raw >> bit) & 1 else 'False'}")
    lines.append("others => <>")
    return lines


def emit_aggregate(out, indent, lines):
    out.write(f"{indent}(")
    pad = " " * (len(indent) + 1)
    out.write((",\n" + pad).join(lines))
    out.write(");\n")


# -- Sections (verified by direct inspection of this XML, not assumed) --
S_CLOCKS = "mss/mss_clocks/clocks/registers"
S_MSS_SYS = "mss/mss_clocks/mss_sys/registers"
S_MSS_PLL = "mss/mss_clocks/mss_pll/registers"
S_MSS_CFM = "mss/mss_clocks/mss_cfm/registers"
S_SGMII_CFM = "mss/mss_clocks/sgmii_cfm/registers"
S_IO_MUX = "mss/mss_io/io_mux/registers"
S_APB_SPLIT = "mss/mss_memory_map/apb_split/registers"

PLAIN_REGISTERS = [
    # (Ada constant name, Ada record type, section, xml register name)
    ("CLOCK_CONFIG_CR_Value", "SYSREG.CLOCK_CONFIG_CR_Register", S_MSS_SYS, "CLOCK_CONFIG_CR"),
    ("RTC_CLOCK_CR_Value", "SYSREG.RTC_CLOCK_CR_Register", S_MSS_SYS, "RTC_CLOCK_CR"),
    ("ENVM_CR_Value", "SYSREG.ENVM_CR_Register", S_MSS_SYS, "ENVM_CR"),
    ("IOMUX0_CR_Value", "SYSREG.IOMUX0_CR_Register", S_IO_MUX, "IOMUX0_CR"),
    ("IOMUX6_CR_Value", "SYSREG.IOMUX6_CR_Register", S_IO_MUX, "IOMUX6_CR"),
    ("MSSIO_BANK2_CFG_CR_Value", "SCB_REGS.MSSIO_BANK2_CFG_CR_Register", S_IO_MUX, "MSSIO_BANK2_CFG_CR"),
    ("MSSIO_BANK4_CFG_CR_Value", "SCB_REGS.MSSIO_BANK4_CFG_CR_Register", S_IO_MUX, "MSSIO_BANK4_CFG_CR"),
    ("PLL_REF_FB_Value", "IOSCB_PLL_MSS.PLL_REF_FB_Register", S_MSS_PLL, "PLL_REF_FB"),
    ("PLL_DIV_0_1_Value", "IOSCB_PLL_MSS.PLL_DIV_0_1_Register", S_MSS_PLL, "PLL_DIV_0_1"),
    ("PLL_DIV_2_3_Value", "IOSCB_PLL_MSS.PLL_DIV_2_3_Register", S_MSS_PLL, "PLL_DIV_2_3"),
    ("PLL_CTRL2_Value", "IOSCB_PLL_MSS.PLL_CTRL2_Register", S_MSS_PLL, "PLL_CTRL2"),
    ("PLL_FRACN_Value", "IOSCB_PLL_MSS.PLL_FRACN_Register", S_MSS_PLL, "PLL_FRACN"),
    ("SSCG_REG_0_Value", "IOSCB_PLL_MSS.SSCG_REG_0_Register", S_MSS_PLL, "SSCG_REG_0"),
    ("SSCG_REG_1_Value", "IOSCB_PLL_MSS.SSCG_REG_1_Register", S_MSS_PLL, "SSCG_REG_1"),
    ("SSCG_REG_2_Value", "IOSCB_PLL_MSS.SSCG_REG_2_Register", S_MSS_PLL, "SSCG_REG_2"),
    ("SSCG_REG_3_Value", "IOSCB_PLL_MSS.SSCG_REG_3_Register", S_MSS_PLL, "SSCG_REG_3"),
    # PLL_PHADJ is NOT here -- see the module docstring's note on
    # REG_OUT3_PHSINIT/REG_LOADPHS_B; the generator refuses to guess.
    ("PLL_CTRL_Value", "IOSCB_PLL_MSS.PLL_CTRL_Register", S_MSS_PLL, "PLL_CTRL"),
    ("PLL_CKMUX_Value", "IOSCB_MUX_MSS.PLL_CKMUX_Register", S_MSS_CFM, "PLL_CKMUX"),
    ("BCLKMUX_Value", "IOSCB_MUX_MSS.BCLKMUX_Register", S_MSS_CFM, "BCLKMUX"),
    ("FMETER_ADDR_Value", "IOSCB_MUX_MSS.FMETER_ADDR_Register", S_MSS_CFM, "FMETER_ADDR"),
    ("FMETER_DATAW_Value", "IOSCB_MUX_MSS.FMETER_DATAW_Register", S_MSS_CFM, "FMETER_DATAW"),
    ("MSSCLKMUX_Value", "IOSCB_MUX_MSS.MSSCLKMUX_Register", S_MSS_CFM, "MSSCLKMUX"),
    ("CLK_XCVR_Value", "IOSCB_MUX_SGMII.CLK_XCVR_Register", S_SGMII_CFM, "CLK_XCVR"),
]
# IOMUX1_CR/IOMUX3_CR/IOMUX4_CR/IOMUX5_CR are Unchecked_Union
# (As_Array discriminant) in the PAC; IOMUX2_CR is a plain record whose
# one field, PAD, is itself that same union shape. All four pack several
# 4-bit PAD<n> fields the PAC does not expose individually (it only
# offers the whole-register Val or the Arr view) -- verified against
# mpfs_pac/src/mpfs_mss-sysreg.ads directly, not assumed. So all five are
# handled the same way: pack every RW PAD<n> field at its own XML offset
# into one integer and emit it as Val.
PACKED_IOMUX = ["IOMUX1_CR", "IOMUX2_CR", "IOMUX3_CR", "IOMUX4_CR", "IOMUX5_CR"]
IOMUX2_NESTED_PAD = "IOMUX2_CR"  # the only one whose Val sits under .PAD

# APBBUS_CR groups each peripheral's flat XML bits into per-peripheral
# union sub-fields in the PAC (MMUART/WDOG/SPI/I2C/CAN/GEM/GPIO each as
# (As_Array => False, Val => ...), TIMER/RTC/H2FINT as plain Booleans) --
# verified against mpfs_mss-sysreg.ads's own representation clause, not
# assumed. (name, bit_lo, bit_hi, is_union)
APBBUS_CR_GROUPS = [
    ("MMUART", 0, 4, True), ("WDOG", 5, 9, True), ("SPI", 10, 11, True),
    ("I2C", 12, 13, True), ("CAN", 14, 15, True), ("GEM", 16, 17, True),
    ("TIMER", 18, 18, False), ("GPIO", 19, 21, True), ("RTC", 22, 22, False),
    ("H2FINT", 23, 23, False),
]

# GPIO_INTERRUPT_FAB_CR is a plain MPFS_MSS.UInt32 in the PAC (not a
# record -- verified against mpfs_mss-sysreg.ads directly), but the XML
# breaks it into 32 individually-named bits. Pack them into one integer
# the same way as PACKED_IOMUX, but emit a bare literal: there is no
# record type to aggregate into.
PACKED_SCALARS = [
    # (Ada constant name, section, xml register name)
    ("GPIO_INTERRUPT_FAB_CR_Value", S_IO_MUX, "GPIO_INTERRUPT_FAB_CR"),
]

IO_CFG_PAIRS = ["0_1", "2_3", "4_5", "6_7", "8_9", "10_11", "12_13"]

CLOCKS = [
    ("Cpu_Hz", "MSS_COREPLEX_CPU_CLK"),
    ("System_Hz", "MSS_SYSTEM_CLK"),
    ("Axi_Hz", "MSS_AXI_CLK"),
    ("Apb_Ahb_Hz", "MSS_APB_AHB_CLK"),
    ("Rtc_Toggle_Hz", "MSS_RTC_TOGGLE_CLK"),
    ("Ddr_Hz", "DDR_CLK"),
    ("Sgmii_Ref_Hz", "MSS_EXT_SGMII_REF_CLK"),
]

os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
with open(OUT_PATH, "w") as out:
    out.write("pragma Style_Checks (Off);\n\n")
    out.write("--  GENERATED by generate_mpfs_config.py -- do not hand-edit.\n")
    out.write(f"--  Source: {os.path.basename(XML_PATH)}\n")
    out.write(f"--  xml_format_version: {fmt_version}\n")
    out.write(f"--  design_name: {design_name}  mpfs_part_no: {part_no}\n")
    out.write(f"--  sha256: {xml_hash}\n\n")
    out.write("with MPFS_MSS.SYSREG;\n")
    out.write("with MPFS_MSS.SCB_REGS;\n")
    out.write("with MPFS_MSS.IOSCB_PLL_MSS;\n")
    out.write("with MPFS_MSS.IOSCB_MUX_MSS;\n")
    out.write("with MPFS_MSS.IOSCB_MUX_SGMII;\n\n")
    out.write("package MPFS_MSS_Config is\n")
    #  Preelaborate, not Pure: it depends on MPFS_MSS.SYSREG etc., which
    #  are themselves only Preelaborate (register-access packages with
    #  Volatile/Import components, which Pure forbids).
    out.write("   pragma Preelaborate;\n\n")
    out.write(f'   XML_Format_Version : constant String := "{fmt_version}";\n')
    out.write(f'   XML_SHA256 : constant String := "{xml_hash}";\n\n')

    out.write("   package Clocks is\n")
    for ada_name, xml_name in CLOCKS:
        value = next(v for n, v, w, rw, off in reg_fields(S_CLOCKS, xml_name) if n == xml_name)
        out.write(f"      {ada_name} : constant := {value};\n")
    out.write("   end Clocks;\n\n")

    for ada_name, ada_type, section, xml_name in PLAIN_REGISTERS:
        out.write(f"   {ada_name} : constant MPFS_MSS.{ada_type} :=\n")
        emit_aggregate(out, "     ", ada_aggregate(section, xml_name))
        out.write("\n")

    for xml_name in PACKED_IOMUX:
        packed = 0
        for n, v, w, is_rw, off in reg_fields(S_IO_MUX, xml_name):
            if is_rw and n.upper().startswith("PAD"):
                packed |= v << off
        out.write(f"   {xml_name}_Value : constant MPFS_MSS.SYSREG.{xml_name}_Register :=\n")
        if xml_name == IOMUX2_NESTED_PAD:
            out.write(f"     (PAD => (As_Array => False, Val => 16#{packed:X}#), others => <>);\n\n")
        else:
            out.write(f"     (As_Array => False, Val => 16#{packed:X}#);\n\n")

    apbbus_packed = 0
    for n, v, w, is_rw, off in reg_fields(S_APB_SPLIT, "APBBUS_CR"):
        if is_rw:
            apbbus_packed |= v << off
    out.write("   APBBUS_CR_Value : constant MPFS_MSS.SYSREG.APBBUS_CR_Register :=\n")
    apbbus_lines = []
    for gname, lo, hi, is_union in APBBUS_CR_GROUPS:
        bits = (apbbus_packed >> lo) & ((1 << (hi - lo + 1)) - 1)
        apbbus_lines.append(f"{gname} => (As_Array => False, Val => 16#{bits:X}#)"
                             if is_union else f"{gname} => {'True' if bits else 'False'}")
    apbbus_lines.append("others => <>")
    emit_aggregate(out, "     ", apbbus_lines)
    out.write("\n")

    for ada_name, section, xml_name in PACKED_SCALARS:
        packed = 0
        for n, v, w, is_rw, off in reg_fields(section, xml_name):
            if is_rw:
                packed |= v << off
        out.write(f"   {ada_name} : constant MPFS_MSS.UInt32 := 16#{packed:X}#;\n\n")

    for bank in (4, 2):
        for pr in IO_CFG_PAIRS:
            lo, hi = pr.split("_")
            name = f"MSSIO_BANK{bank}_IO_CFG_{pr}_CR"
            out.write(f"   {name}_Value : constant "
                      f"MPFS_MSS.SYSREG.{name}_Register :=\n")
            emit_aggregate(out, "     ", ada_io_cfg_pair(S_IO_MUX, name, lo, hi))
            out.write("\n")

    out.write("end MPFS_MSS_Config;\n")

print(f"wrote {OUT_PATH}")
print(f"xml_format_version={fmt_version} design_name={design_name} "
      f"mpfs_part_no={part_no} sha256={xml_hash[:16]}...")
