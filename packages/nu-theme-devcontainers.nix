{ pkgs, ... }:
pkgs.writeTextDir "share/nushell/vendor/autoload/50-devcontainers-theme.nu" (
  builtins.readFile ./devcontainers-theme.nu
)
