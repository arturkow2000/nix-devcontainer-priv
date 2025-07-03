{ self, inputs, ... }:
let
  inherit (inputs.nixpkgs) lib;

  baseModules = import ../modules/module-list.nix {
    upstreamModulePath = "${inputs.nixpkgs.outPath}/nixos/modules";
  };

  parsedArchToFlake = parsed: "${parsed.cpu.name}-${parsed.kernel.name}";

  mkDefaultConfig =
    {
      name,
      defaultShell,
      enabledShells,
      shellTheme,
      defaultUser,
      copyNixpkgs,
    }:
    { config, pkgs, ... }:
    {
      assertions = [
        {
          assertion =
            shellTheme == null
            || lib.elem shellTheme [
              "devcontainers"
              "starship"
            ];
          message = "Unsupported shell theme \"${shellTheme}\"";
        }
      ];

      system.nixos.containerName = name;
      system.stateVersion = lib.mkDefault lib.trivial.release;
      programs = lib.mkMerge [
        (lib.foldl' (acc: x: acc // { ${x}.enable = true; }) { } (
          # bash is always enabled in NixOS
          lib.filter (x: x != "bash") enabledShells
        ))
        {
          zsh.ohMyZsh = {
            enable = lib.mkDefault true;
            theme = lib.mkIf (shellTheme != null && shellTheme != "starship") shellTheme;
            customPkgs = lib.optional (shellTheme == "devcontainers") (
              pkgs.callPackage ../packages/zsh-theme-devcontainers.nix { }
            );
          };
        }
        {
          bash.promptInit = lib.mkIf (shellTheme == "devcontainers") ''
            source ${pkgs.callPackage ../packages/bash-theme-devcontainers.nix { }}
          '';
        }
        (lib.mkIf (shellTheme == "starship") {
          starship.enable = true;
        })
        {
          # Make default as vscode, intellij, and all dynamically linked non-NixOS binaries need this.
          nix-ld = {
            enable = lib.mkDefault true;
            # vscode needs libstdc++
            libraries = [ pkgs.stdenv.cc.cc.lib ];
          };
        }
        {
          git.enable = lib.mkDefault true;
        }
      ];
      users = lib.mkMerge [
        { defaultUserShell = pkgs.${defaultShell}; }
        (lib.mkIf (defaultUser != null) {
          users.${defaultUser.name} = {
            inherit (defaultUser) uid;

            isNormalUser = true;
            group = defaultUser.name;
            extraGroups = [ "users" ];
          };
          groups.${defaultUser.name} = { inherit (defaultUser) gid; };
        })
      ];
      security.sudo.extraRules = lib.optional (defaultUser.sudoNopasswd or true) {
        users = [ defaultUser.name ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      };
      nix = {
        enable = lib.mkDefault true;
        extraOptions = ''
          extra-experimental-features = nix-command flakes
        '';
        allowedUsers = lib.optional (defaultUser != null) defaultUser.name;
        nixPath = lib.optional copyNixpkgs "nixpkgs=${pkgs.path}";
        registry.nixpkgs.flake = lib.mkIf copyNixpkgs inputs.nixpkgs;
      };
    };

  mkDevcontainer = lib.makeOverridable (
    args:
    {
      name ? "nix-container",
      defaultShell ? "zsh",
      enabledShells ? [ defaultShell ],
      shellTheme ? "devcontainers",
      defaultUser ? {
        name = "vscode";
        uid = 1000;
        gid = 1000;
        sudoNopasswd = true;
      },
      packages ? [ ],
      copyNixpkgs ? false,
    }:
    let
      system = lib.nixosSystem (
        {
          lib = args.lib or lib;
          modules = [
            (mkDefaultConfig {
              inherit
                name
                defaultShell
                enabledShells
                shellTheme
                defaultUser
                copyNixpkgs
                ;
            })
            {
              environment.systemPackages = packages;
            }
          ] ++ (args.modules or [ ]);
          inherit baseModules;

          specialArgs = {
            flake = self;
            inherit parsedArchToFlake;
          };
        }
        // (builtins.removeAttrs args [
          "lib"
          "modules"
        ])
      );

      metaDerivation =
        system.pkgs.runCommandNoCC system.config.system.build.toplevel.name
          {
            passAsFile = [ "text" ];
            text = ''
              #!${system.pkgs.buildPackages.runtimeShell}
              cat >&2 << EOF
              You need to use container runtime like Docker or Podman to run this container.

              To copy the container use either "copyToDockerDaemon" or "copyToPodman".
              Example:
                nix run .#container.copyToDockerDaemon
                nix run .#container.copyToPodman

              Alternatively, you may take advantage of nix-snapshotter to avoid copying data,
              instead running the container directly from Nix store.
              This requires nix-snapshotter to be setup on your system (refer to https://github.com/pdtpartners/nix-snapshotter for instructions).
              To register the image with containerd use:
                nix run .#container.useNixSnapshotter.copyToContainerd

              To register the image with Docker, register the image with "moby" namespace.
              This requires direct access to the same instance of containerd that Docker uses internally:
                nix run .#container.useNixSnapshotter.copyToContainerd -- -n moby

              Additionally, for Nix containers to work in Docker you need to enable containerd snapshotters
              and set nix snapshotter as Docker storage driver. On NixOS this can be done using:

              virtualisation.docker.daemon.settings = {
                features.containerd-snapshotter = true;
                storage-driver = "nix";
              };
              EOF
              exit 1
            '';

            meta.mainProgram = system.config.system.build.toplevel.name;
            passthru = {
              inherit (system) config;
              inherit (system.config.system.build.nix2container) copyToPodman copyToDockerDaemon;
              useNixSnapshotter = {
                # Use custom wrapper that allows us to specify address and namespace at runtime
                # instead of at instantiation time which doesn't play well with nix run.
                copyToContainerd = system.pkgs.writeShellScriptBin "copy-to-containerd" ''
                  set -euo pipefail

                  usage() {
                  cat << EOF
                  Usage: $0 [options]

                  Options:
                   -a, --address <address>\tcontainerd address
                   -n, --namespace <namespace>\tcontainerd namespace
                  EOF
                  exit 1
                  }

                  args=$(getopt -o ha:n: -l help,address:,namespace: -- "$@")
                  [[ $? -gt 0 ]] && usage

                  address=""
                  namespace=""

                  eval set -- ''${args}
                  while :
                  do
                    case "$1" in
                      -h | --help) usage ;;
                      -a | --address) address="$2" ; shift 2 ;;
                      -n | --namespace) namespace="$2"; shift 2 ;;
                      --) shift; break ;;
                      *) usage ;;
                    esac
                  done

                  [[ $# -gt 0 ]] && usage

                  args=()
                  [ -n "$address" ] && args+=(--address "$address")
                  [ -n "$namespace" ] && args+=(--namespace "$namespace")
                  args+=(load ${system.config.system.build.nix-snapshotter})
                  exec "${
                    self.inputs.nix-snapshotter.packages.${parsedArchToFlake system.config.nixpkgs.buildPlatform.parsed}.nix-snapshotter
                  }/bin/nix2container" "''${args[@]}"
                '';

                copyToDockerDaemon = system.pkgs.writeShellScriptBin "copy-to-docker" ''
                  set -euo pipefail

                  usage() {
                  cat << EOF
                  Usage: $0 [options]
                  EOF
                  }

                  args=$(getopt -o h -l help -- "$@")
                  [[ $? -gt 0 ]] && usage

                  eval set -- ''${args}
                  while :
                  do
                    case "$1" in
                      -h | --help) usage ;;
                      --) shift; break ;;
                      *) usage ;;
                    esac
                  done

                  [[ $# -gt 0 ]] && usage

                  args=(load -i ${system.config.system.build.nix-snapshotter})
                  exec "${lib.getExe system.pkgs.docker}" "''${args[@]}"
                '';
              };
            };
          }
          ''
            mkdir -p $out/bin
            mv "$textPath" "$out/bin/${system.config.system.build.toplevel.name}"
            chmod +x "$out/bin/${system.config.system.build.toplevel.name}"

            ln -s "${system.config.system.build.nix2container}" $out/image.json
            ln -s "${system.config.system.build.nix-snapshotter}" $out/image.nix-snapshotter.tar
          '';
    in
    metaDerivation
  ) { };
in
{
  flake.lib = {
    inherit mkDevcontainer;
  };
}
