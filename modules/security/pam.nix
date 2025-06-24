{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.security.pam;
in
{
  options = {
    security.pam.package = lib.mkPackageOption pkgs "pam" { };
  };

  config = {
    environment.systemPackages = [ cfg.package ];
  };
}
