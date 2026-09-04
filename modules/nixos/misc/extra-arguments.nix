{
  lib,
  config,
  pkgs,
  ...
}:
let
  prev = import "${pkgs.path}/nixos/lib/utils.nix" { inherit lib config pkgs; };
  toShellPath =
    shell:
    if lib.types.shellPackage.check shell then "/usr${shell.shellPath}" else prev.toShellPath shell;
in
{
  _module.args.utils = prev // {
    inherit toShellPath;
  };
}
