# Based on nixpkgs ff8d74d0097bbdcf430e5e866c0c1d795f138ab4
# Adapted for containers (statically created links, no systemd dependency).
{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    last
    splitString
    mkOption
    types
    optionals
    ;

  libDir = pkgs.stdenv.hostPlatform.libDir;
  ldsoBasename = builtins.unsafeDiscardStringContext (
    last (splitString "/" pkgs.stdenv.cc.bintools.dynamicLinker)
  );

  # Hard-code to avoid creating another instance of nixpkgs. Also avoids eval errors in some cases.
  libDir32 = "lib"; # pkgs.pkgsi686Linux.stdenv.hostPlatform.libDir
  ldsoBasename32 = "ld-linux.so.2"; # last (splitString "/" pkgs.pkgsi686Linux.stdenv.cc.bintools.dynamicLinker)
in
{
  options = {
    environment.ldso = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        The executable to link into the normal FHS location of the ELF loader.
      '';
    };

    environment.ldso32 = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        The executable to link into the normal FHS location of the 32-bit ELF loader.

        This currently only works on x86_64 architectures.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = isNull config.environment.ldso32 || pkgs.stdenv.hostPlatform.isx86_64;
        message = "Option environment.ldso32 currently only works on x86_64.";
      }
    ];

    environment.pathsToLink =
      lib.optional (config.environment.ldso != null) "/${libDir}"
      ++ lib.optional (config.environment.ldso32 != null) "/${libDir32}";
    environment.systemPackages = [
      (pkgs.runCommandNoCCLocal "ldso" { } (
        lib.optionalString (config.environment.ldso != null) ''
          mkdir -p $out/${libDir}
          ln -s ${config.environment.ldso} $out/${libDir}/${ldsoBasename}
        ''
        + lib.optionalString (config.environment.ldso32 != null) ''
          mkdir -p $out/${libDir32}
          ln -s ${config.environment.ldso32} $out/${libDir32}/${ldsoBasename32}
        ''
      ))
    ];
    system.extraSystemBuilderCmds =
      lib.optionalString (config.environment.ldso != null) ''
        ln -s /usr/${libDir} $out/
      ''
      + lib.optionalString (config.environment.ldso32 != null) ''
        ln -s /usr/${libDir32} $out/
      '';
  };

  meta.maintainers = with lib.maintainers; [ tejing ];
}
