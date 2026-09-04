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
  cfg = config.programs.bash.undistractMe;
in
{
  options = {
    programs.bash.undistractMe = {
      enable = lib.mkEnableOption "notifications when long-running terminal commands complete";

      playSound = lib.mkEnableOption "notification sounds when long-running terminal commands complete";

      timeout = lib.mkOption {
        default = 10;
        description = ''
          Number of seconds it would take for a command to be considered long-running.
        '';
        type = lib.types.int;
      };
    };
  };

  config = lib.mkIf cfg.enable {
    programs.bash.promptPluginInit = ''
      export LONG_RUNNING_COMMAND_TIMEOUT=${toString cfg.timeout}
      export UDM_PLAY_SOUND=${if cfg.playSound then "1" else "0"}
      . "${pkgs.undistract-me}/etc/profile.d/undistract-me.sh"
    '';
  };

  meta = {
    maintainers = with lib.maintainers; [ kira-bruneau ];
  };
}
