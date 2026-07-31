--  The renaming shim (CONTRACT.md §3.3). Alire generates
--  gnat_config/light_tasking_mpfs_config.ads, whose name embeds the
--  profile; shared tier-2/tier-3 sources cannot `with` a name that varies
--  per leaf, so every leaf commits this indirection under the one stable
--  name, MPFS_Runtime_Config.
--
--  It lives in src/, not in gnat_config/, so that Alire's generated output
--  and hand-written files are not mixed in one directory. It is named in
--  the gnat-side Source_List_File only; the libgnarl half reaches it as a
--  cross-library reference through ada_source_path, which is why there is
--  no gnarl-side copy (there used to be an identical one, in gnarl_user/,
--  that no membership list ever named).

pragma Restrictions (No_Elaboration_Code);
pragma Style_Checks (Off);

with Light_Tasking_Mpfs_Config;
package MPFS_Runtime_Config renames Light_Tasking_Mpfs_Config;
