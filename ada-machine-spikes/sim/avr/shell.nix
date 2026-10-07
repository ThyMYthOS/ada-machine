# Local (macOS/Linux) shell for the simavr harness: `nix-shell` here, then
# `make run`. CI uses apt instead (Ubuntu's libsimavr-dev).
# nixpkgs' simavr.pc has an empty prefix, so the Makefile is pointed at the
# store path directly through SIMAVR_PREFIX.
{ pkgs ? import <nixpkgs> { } }:
pkgs.mkShell {
  packages = [ pkgs.simavr pkgs.libelf pkgs.python3 ];
  SIMAVR_PREFIX = "${pkgs.simavr}";
}
