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

  cfg = config.programs.htop;

  fmt =
    value:
    if builtins.isList value then
      builtins.concatStringsSep " " (map fmt value)
    else if builtins.isString value then
      value
    else if builtins.isBool value then
      if value then "1" else "0"
    else if builtins.isInt value then
      toString value
    else
      throw "Unrecognized type ${builtins.typeOf value} in htop settings";

in

{

  options.programs.htop = {
    package = lib.mkPackageOption pkgs "htop" { };

    enable = lib.mkEnableOption "htop process monitor";

    settings = lib.mkOption {
      type =
        with lib.types;
        attrsOf (oneOf [
          str
          int
          bool
          (listOf (oneOf [
            str
            int
            bool
          ]))
        ]);
      default = { };
      example = {
        hide_kernel_threads = true;
        hide_userland_threads = true;
      };
      description = ''
        Extra global default configuration for htop
        which is read on first startup only.
        Htop subsequently uses ~/.config/htop/htoprc
        as configuration source.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
    ];

    environment.etc."htoprc".text = ''
      # Global htop configuration
      # To change set: programs.htop.settings.KEY = VALUE;
    ''
    + builtins.concatStringsSep "\n" (
      lib.mapAttrsToList (key: value: "${key}=${fmt value}") cfg.settings
    );
  };

}
