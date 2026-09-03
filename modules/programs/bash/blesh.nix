# Vendored from nixpkgs rev ff8d74d0097bbdcf430e5e866c0c1d795f138ab4
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
