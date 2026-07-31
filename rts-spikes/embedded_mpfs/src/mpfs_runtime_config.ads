pragma Restrictions (No_Elaboration_Code);
pragma Style_Checks (Off);

--  CONTRACT.md §3.3: the renaming shim. Alire generates
--  gnat_config/embedded_mpfs_config.ads (named after this crate), but the
--  tier-2/tier-3 sources shared with light_mpfs and light_tasking_mpfs
--  cannot `with` a name that varies per leaf. Every leaf therefore commits
--  this one-line indirection under the same stable name, MPFS_Runtime_Config,
--  renaming its own crate's generated config package -- Embedded_Mpfs_Config
--  here (RTS.md §5.1).

with Embedded_Mpfs_Config;
package MPFS_Runtime_Config renames Embedded_Mpfs_Config;
