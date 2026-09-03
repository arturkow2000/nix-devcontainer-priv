# Vendored from nixpkgs rev ff8d74d0097bbdcf430e5e866c0c1d795f138ab4
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
  cfg = config.programs.git-worktree-switcher;

  initScript =
    shell:
    if (shell == "fish") then
      ''
        ${lib.getExe pkgs.git-worktree-switcher} init ${shell} | source
      ''
    else
      ''
        eval "$(${lib.getExe pkgs.git-worktree-switcher} init ${shell})"
      '';
in
{
  options = {
    programs.git-worktree-switcher = {
      enable = lib.mkEnableOption "git-worktree-switcher, switch between git worktrees with speed.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ git-worktree-switcher ];

    programs.bash.interactiveShellInit = initScript "bash";
    programs.zsh.interactiveShellInit = lib.optionalString config.programs.zsh.enable (
      initScript "zsh"
    );
    programs.fish.interactiveShellInit = lib.optionalString config.programs.fish.enable (
      initScript "fish"
    );
  };
}
