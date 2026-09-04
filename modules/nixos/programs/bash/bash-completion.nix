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
  cfg = config.programs.bash;
in
{
  options.programs.bash.completion = {
    enable = lib.mkEnableOption "Bash completion for all interactive bash shells" // {
      default = true;
    };

    package = lib.mkPackageOption pkgs "bash-completion" { };
  };

  imports = [
    (lib.mkRenamedOptionModule
      [ "programs" "bash" "enableCompletion" ]
      [ "programs" "bash" "completion" "enable" ]
    )
  ];

  config = lib.mkIf cfg.completion.enable {
    programs.bash.promptPluginInit = ''
      # Check whether we're running a version of Bash that has support for
      # programmable completion. If we do, enable all modules installed in
      # the system and user profile in obsolete /etc/bash_completion.d/
      # directories. Bash loads completions in all
      # $XDG_DATA_DIRS/bash-completion/completions/
      # on demand, so they do not need to be sourced here.
      if shopt -q progcomp &>/dev/null; then
        . "${cfg.completion.package}/etc/profile.d/bash_completion.sh"
        nullglobStatus=$(shopt -p nullglob)
        shopt -s nullglob
        for p in $NIX_PROFILES; do
          for m in "$p/etc/bash_completion.d/"*; do
            . "$m"
          done
        done
        eval "$nullglobStatus"
        unset nullglobStatus p m
      fi
    '';
  };
}
