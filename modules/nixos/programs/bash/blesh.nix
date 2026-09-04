# Vendored from nixpkgs rev 24a69cdc73f76df4dde9edabcda6737f55b66627
# by util/vendor-nixos-modules.py. If modification is required, remember to remove
# this module from modules_to_vendor list in util/vendor-nixos-modules.py, or changes
# will be overridden on next vendoring.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.programs.bash.blesh;
in
{
  options = {
    programs.bash.blesh.enable = lib.mkEnableOption "blesh, a full-featured line editor written in pure Bash";
  };

  config = lib.mkIf cfg.enable {
    programs.bash.interactiveShellInit = lib.mkBefore ''
      source ${pkgs.blesh}/share/blesh/ble.sh
    '';
  };
  meta.maintainers = with lib.maintainers; [ laalsaas ];
}
