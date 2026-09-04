# Vendored from nixpkgs rev ff8d74d0097bbdcf430e5e866c0c1d795f138ab4
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
  cfg = config.programs.nano;
in

{
  options = {
    programs.nano = {
      enable = lib.mkEnableOption "nano, a small user-friendly console text editor" // {
        default = true;
      };

      package = lib.mkPackageOption pkgs "nano" { };

      nanorc = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = ''
          The system-wide nano configuration.
          See {manpage}`nanorc(5)`.
        '';
        example = ''
          set nowrap
          set tabstospaces
          set tabsize 2
        '';
      };

      syntaxHighlight = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to enable syntax highlight for various languages.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment = {
      etc.nanorc.text =
        (lib.optionalString cfg.syntaxHighlight ''
          # load syntax highlighting files
          include "${cfg.package}/share/nano/*.nanorc"
          include "${cfg.package}/share/nano/extra/*.nanorc"
        '')
        + cfg.nanorc;
      systemPackages = [ cfg.package ];
      pathsToLink = [ "/share/nano" ];
    };
  };
}
