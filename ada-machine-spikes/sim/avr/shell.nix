# Local (macOS/Linux) shell for the simavr harness: `nix-shell` here, then
# `make run`. CI builds the same simavr release (v1.7) from source, since
# Ubuntu (24.04 through 26.04) only packages 1.6, whose TWI model differs.
# nixpkgs' simavr.pc has an empty prefix, so the Makefile is pointed at the
# store path directly through SIMAVR_PREFIX.
{ pkgs ? import <nixpkgs> { } }:
pkgs.mkShell {
  packages = [ pkgs.simavr pkgs.libelf pkgs.python3 ];
  SIMAVR_PREFIX = "${pkgs.simavr}";
}
