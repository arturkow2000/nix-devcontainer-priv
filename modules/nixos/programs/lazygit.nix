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
  cfg = config.programs.lazygit;

  settingsFormat = pkgs.formats.yaml { };
in
{
  options.programs.lazygit = {
    enable = lib.mkEnableOption "lazygit, a simple terminal UI for git commands";

    package = lib.mkPackageOption pkgs "lazygit" { };

    settings = lib.mkOption {
      inherit (settingsFormat) type;
      default = { };
      description = ''
        Lazygit configuration.

        See <https://github.com/jesseduffield/lazygit/blob/master/docs/Config.md> for documentation.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment = {
      systemPackages = [ cfg.package ];
      etc = lib.mkIf (cfg.settings != { }) {
        "xdg/lazygit/config.yml".source = settingsFormat.generate "lazygit-config.yml" cfg.settings;
      };
    };
  };

  meta = {
    maintainers = with lib.maintainers; [ linsui ];
  };
}
