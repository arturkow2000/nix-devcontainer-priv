# Based on nixpkgs 24a69cdc73f76df4dde9edabcda6737f55b66627
# Changes:
# - removed dependency on systemd
# - removed per-user channels (only global config is supported)
/*
  Manages the things that are needed for a traditional nix-channel based
  configuration to work.

  See also
  - ./nix.nix
  - ./nix-flakes.nix
*/
{ config, lib, ... }:
let
  inherit (lib)
    mkIf
    mkOption
    types
    ;
  cfg = config.nix;
in
{
  options = {
    nix = {
      channel = {
        enable = mkOption {
          description = ''
            Whether the `nix-channel` command and state files are made available on the machine.

            The following files are initialized when enabled:
              - `/nix/var/nix/profiles/per-user/root/channels`

            Disabling this option will not remove the state files from the system.
          '';
          type = types.bool;
          default = true;
        };
      };

      nixPath = mkOption {
        type = types.listOf types.str;
        default =
          if cfg.channel.enable then
            [
              "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"
            ]
          else
            [ ];
        defaultText = ''
          if nix.channel.enable
          then [
            "nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos"
          ]
          else [];
        '';
        description = ''
          The default Nix expression search path, used by the Nix
          evaluator to look up paths enclosed in angle brackets
          (e.g. `<nixpkgs>`).
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    environment.variables = {
      NIX_PATH = cfg.nixPath;
    };
  };
}
