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
  cfg = config.programs.git-worktree-switcher;

  initScript =
    shell:
    if (shell == "fish") then
      ''
        ${lib.getExe cfg.package} init ${shell} | source
      ''
    else
      ''
        eval "$(${lib.getExe cfg.package} init ${shell})"
      '';
in
{
  options = {
    programs.git-worktree-switcher = {
      enable = lib.mkEnableOption "git-worktree-switcher, switch between git worktrees with speed.";
      package = lib.mkPackageOption pkgs "git-worktree-switcher" { };
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
