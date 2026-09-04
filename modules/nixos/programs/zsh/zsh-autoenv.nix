# Vendored from nixpkgs rev 24a69cdc73f76df4dde9edabcda6737f55b66627
# by util/vendor-nixos-modules.py. If modification is required, remember to remove
# this module from modules_to_vendor list in util/vendor-nixos-modules.py, or changes
# will be overridden on next vendoring.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.zsh.zsh-autoenv;
in
{
  options = {
    programs.zsh.zsh-autoenv = {
      enable = lib.mkEnableOption "zsh-autoenv";
      package = lib.mkPackageOption pkgs "zsh-autoenv" { };
    };
  };

  config = lib.mkIf cfg.enable {
    programs.zsh.interactiveShellInit = ''
      source ${cfg.package}/share/zsh-autoenv/autoenv.zsh
    '';
  };
}
