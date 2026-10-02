#!/bin/sh
#  toolchains.sh -- make sure the two pinned cross compilers are installed.
#  Driven by `make toolchains` (a prerequisite of `populate`, hence of `build`).
#
#  WHY THIS EXISTS (RTS-PRODUCTION.md A3). populate.sh copies tier 1 out of the
#  installed gnat_riscv64_elf / gnat_arm_elf toolchains. On a machine that has
#  never built anything those directories do not exist, and the only thing in
#  the old flow that created them was `alr build` -- which runs AFTER populate.
#  So `make build` stopped at "gnat_riscv64_elf 15.3.1 not installed" on every
#  fresh machine, and the "prerequisite" was something a person had to have done
#  by hand, once, without being told how.
#
#  HOW. The compilers are ordinary Alire dependencies of the leaf runtimes
#  (`gnat_riscv64_elf = "=15.3.1"` in light_mpfs etc.), so asking Alire to get
#  an application's dependencies installs them. `alr build --stop-after=
#  post-fetch` does exactly that and stops before any compilation, which is why
#  it can run before populate. (`alr toolchain --select` is NOT used: it would
#  make a cross compiler the user's DEFAULT gnat.)
#
#  Idempotent and silent about the network when everything is there. Fails, with
#  the directory it looked in and the one Alire says it uses, when Alire "succeeds"
#  but the compiler is not where the Makefile and populate.sh will look.
#
#  Inputs (environment, set by the Makefile):
#    GNAT_VERSION   15.3.1
#    ALIRE_TC_DIR   <alire cache>/toolchains   (default $HOME/.local/share/alire/toolchains)
#
#  POSIX sh only.

set -u

GNAT_VERSION=${GNAT_VERSION:-15.3.1}
ALIRE_TC_DIR=${ALIRE_TC_DIR:-$HOME/.local/share/alire/toolchains}
here=$(cd "$(dirname "$0")" && pwd)

#  crate:application. Any application depending on the crate would do, since
#  Alire deploys the whole solution; one per toolchain keeps it obvious.
pairs="gnat_riscv64_elf:hello_mpfs gnat_arm_elf:hello_rp2040"

installed() {   # crate -> prints the bin dir, or nothing
  ls -d "$ALIRE_TC_DIR/$1_${GNAT_VERSION}"_*/bin 2>/dev/null | head -n 1
}

status=0
for pair in $pairs; do
  crate=${pair%%:*}
  app=${pair#*:}

  have=$(installed "$crate")
  if [ -n "$have" ]; then
    printf '  %s %s: present (%s)\n' "$crate" "$GNAT_VERSION" "$have"
    continue
  fi

  if ! command -v alr >/dev/null 2>&1; then
    printf 'error: %s %s is not installed under %s and `alr` is not on PATH.\n' "$crate" "$GNAT_VERSION" "$ALIRE_TC_DIR" >&2
    printf '       Install Alire (https://alire.ada.dev) and re-run `make toolchains`.\n' >&2
    exit 1
  fi

  printf '  %s %s: not installed; fetching through Alire (first run only; needs network)\n' "$crate" "$GNAT_VERSION"
  printf '    (cd %s && alr -n build --stop-after=post-fetch)\n' "$app"
  if ! ( cd "$here/$app" && alr -n build --stop-after=post-fetch ); then
    printf 'error: alr could not fetch the dependencies of %s, so %s %s is still missing.\n' "$app" "$crate" "$GNAT_VERSION" >&2
    status=1
    continue
  fi

  have=$(installed "$crate")
  if [ -z "$have" ]; then
    printf 'error: alr succeeded but %s_%s_* is not under %s.\n' "$crate" "$GNAT_VERSION" "$ALIRE_TC_DIR" >&2
    printf '       Alire reports: %s\n' "$(alr version 2>/dev/null | grep -i 'cache folder')" >&2
    printf '       Contents of %s:\n' "$ALIRE_TC_DIR" >&2
    ls "$ALIRE_TC_DIR" 2>&1 | sed 's/^/         /' >&2
    printf '       If Alire is using a different cache folder, pass ALIRE_TC_DIR=<that>/toolchains to make.\n' >&2
    printf '       If a different version was installed, the manifests no longer pin %s.\n' "$GNAT_VERSION" >&2
    status=1
    continue
  fi
  printf '  %s %s: installed (%s)\n' "$crate" "$GNAT_VERSION" "$have"
done

exit $status
