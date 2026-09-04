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
              - `/root/.nix-channels`
              - `$HOME/.nix-defexpr/channels` (on login)

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
