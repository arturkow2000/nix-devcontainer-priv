# Vendored from nixpkgs rev 24a69cdc73f76df4dde9edabcda6737f55b66627
# by util/vendor-nixos-modules.py. If modification is required, remember to remove
# this module from modules_to_vendor list in util/vendor-nixos-modules.py, or changes
# will be overridden on next vendoring.
{
  config,
  pkgs,
  lib,
  ...
}:
let

  vteInitSnippet = ''
    # Show current working directory in VTE terminals window title.
    # Supports both bash and zsh, requires interactive shell.
    . ${
      pkgs.vte.override {
        withApp = false;
        gtkVersion = null;
      }
    }/etc/profile.d/vte.sh
  '';

in

{

  meta = {
    teams = [ lib.teams.gnome ];
  };

  options = {

    programs.bash.vteIntegration = lib.mkOption {
      default = false;
      type = lib.types.bool;
      description = ''
        Whether to enable Bash integration for VTE terminals.
        This allows it to preserve the current directory of the shell
        across terminals.
      '';
    };

    programs.zsh.vteIntegration = lib.mkOption {
      default = false;
      type = lib.types.bool;
      description = ''
        Whether to enable Zsh integration for VTE terminals.
        This allows it to preserve the current directory of the shell
        across terminals.
      '';
    };

  };

  config = lib.mkMerge [
    (lib.mkIf config.programs.bash.vteIntegration {
      programs.bash.interactiveShellInit = lib.mkBefore vteInitSnippet;
    })

    (lib.mkIf config.programs.zsh.vteIntegration {
      programs.zsh.interactiveShellInit = vteInitSnippet;
    })
  ];
}
