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
  prg = config.programs;
  cfg = prg.bash-my-aws;

  initScript = ''
    eval $(${pkgs.bash-my-aws}/bin/bma-init)
  '';
in
{
  options = {
    programs.bash-my-aws = {
      enable = lib.mkEnableOption "bash-my-aws";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ bash-my-aws ];

    programs.bash.interactiveShellInit = initScript;
  };
}
