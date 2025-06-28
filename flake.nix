{
  description = "Nix devcontainer";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-snapshotter = {
      url = "github:pdtpartners/nix-snapshotter";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-parts,
      ...
    }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];
      imports = [ ./lib ];

      flake.overlays =
        let
          overlay = final: prev: {
            mkDevcontainer = self.lib.mkDevcontainer.override {
              modules = [
                {
                  nixpkgs.hostPlatform = prev.stdenv.hostPlatform;
                }
              ];
            };
          };
        in
        {
          default = overlay;
          nix-devcontainer = overlay;
        };

      perSystem =
        { inputs', ... }:
        let
          devPackages = with pkgs; [ llvmPackages_latest.clang ];
          pkgs = inputs'.nixpkgs.legacyPackages.extend self.overlays.nix-devcontainer;
        in
        {
          devShells.clang = pkgs.mkShellNoCC {
            packages = devPackages;
          };
          packages.container-clang = pkgs.mkDevcontainer {
            name = "nix-devcontainer-clang";
            packages = devPackages;
          };
        };
    };
}
