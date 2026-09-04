{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nix;
  nixPackage = cfg.package.out;
  isNixAtLeast = lib.versionAtLeast (nixPackage.nixVersion or (lib.getVersion nixPackage));
in
{
  options = {
    nix = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to enable Nix.
          Disabling Nix makes the system hard to modify and the Nix programs and configuration will not be made available by NixOS itself.
        '';
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.nix;
        defaultText = lib.literalExpression "pkgs.nix";
        description = ''
          This option specifies the Nix package instance to use throughout the system.
        '';
      };
    };
  };

  config = {
    environment.systemPackages = [
      nixPackage
      pkgs.nix-info
    ] ++ lib.optional (config.programs.bash.completion.enable) pkgs.nix-bash-completions;

    nix.settings = lib.mkMerge [
      (lib.mkIf (isNixAtLeast "2.3pre") { sandbox-fallback = false; })
    ];
  };
}
