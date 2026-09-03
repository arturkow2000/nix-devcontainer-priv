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
        { system, inputs', ... }:
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
          # Private stuff for CI/CD, kept as legacy so they are hidden from nix flake show.
          legacyPackages =
            let
              inherit (inputs.nixpkgs) lib;
              baseModules = import ./modules/module-list.nix {
                upstreamModulePath = "${pkgs.path}/nixos/modules";
              };
              optionsToJSON =
                { options }:
                let
                  rawOpts = builtins.listToAttrs (
                    map (value: {
                      inherit (value) name;
                      inherit value;
                    }) (lib.optionAttrSetToDocList options)
                  );
                  filterEntries = n: v: !lib.any (v: v == "_module") v.loc;
                  filterFields =
                    v:
                    removeAttrs v [
                      "declarations"
                      "loc"
                      "name"
                    ];
                in
                lib.pipe rawOpts [
                  (lib.filterAttrs filterEntries)
                  (lib.mapAttrs (_: filterFields))
                  builtins.toJSON
                ];
              optionsToJSONDrv =
                args:
                let
                  options = optionsToJSON args;
                in
                pkgs.runCommand "options.json"
                  {
                    nativeBuildInputs = with pkgs; [ jq ];
                    passAsFile = [ "options" ];
                    options = builtins.unsafeDiscardStringContext options;
                  }
                  ''
                    cat "$optionsPath" | jq > "$out"
                  '';
            in
            {
              __nix-devcontainer-options = optionsToJSONDrv {
                options =
                  (lib.evalModules {
                    modules = baseModules ++ [
                      {
                        # Required, or eval will fail.
                        nixpkgs.hostPlatform = system;
                      }
                    ];
                  }).options;
              };
              __nixos-options = optionsToJSONDrv {
                options =
                  (lib.nixosSystem {
                    modules = [
                      ({ config, ... }: {
                        # Required, or eval will fail.
                        nixpkgs.hostPlatform = system;
                        # silence warning
                        system.stateVersion = config.system.nixos.release;
                      })
                    ];
                  }).options;
              };
            };
        };
    };
}
