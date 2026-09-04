{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Custom program that uses gnulib to convert permission string representation into octal form.
  # This provides 100% compatibility with upstream implementation which uses chmod.
  mode2octal = pkgs.buildPackages.callPackage ../../../../util/mode2octal { };

  wrappers = lib.filterAttrs (name: value: value.enable) config.security.wrappers;

  # This is security-sensitive code, and glibc vulns happen from time to time.
  # musl is security-focused and generally more minimal, so it's a better choice here.
  # The dynamic linker is still a fairly complex piece of code, and the wrappers are
  # quite small, so linking it statically is more appropriate.
  securityWrapper =
    sourceProg:
    pkgs.pkgsStatic.callPackage "${pkgs.path}/nixos/modules/security/wrappers/wrapper.nix" {
      inherit sourceProg;

      # glibc definitions of insecure environment variables
      #
      # We extract the single header file we need into its own derivation,
      # so that we don't have to pull full glibc sources to build wrappers.
      #
      # They're taken from pkgs.glibc so that we don't have to keep as close
      # an eye on glibc changes. Not every relevant variable is in this header,
      # so we maintain a slightly stricter list in wrapper.c itself as well.
      unsecvars = lib.overrideDerivation (pkgs.srcOnly pkgs.glibc) (
        { name, ... }:
        {
          name = "${name}-unsecvars";
          installPhase = ''
            mkdir $out
            cp sysdeps/generic/unsecvars.h $out
          '';
        }
      );
    };

  fileModeType =
    let
      # taken from the chmod(1) man page
      symbolic = "[ugoa]*([-+=]([rwxXst]*|[ugo]))+|[-+=][0-7]+";
      numeric = "[-+=]?[0-7]{0,4}";
      mode = "((${symbolic})(,${symbolic})*)|(${numeric})";
    in
    lib.types.strMatching mode // { description = "file mode string"; };

  wrapperType = lib.types.submodule (
    { name, config, ... }:
    {
      options.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to enable the wrapper.";
      };
      options.source = lib.mkOption {
        type = lib.types.path;
        description = "The absolute path to the program to be wrapped.";
      };
      options.program = lib.mkOption {
        type = with lib.types; nullOr str;
        default = name;
        description = ''
          The name of the wrapper program. Defaults to the attribute name.
        '';
      };
      options.owner = lib.mkOption {
        type = lib.types.str;
        description = "The owner of the wrapper program.";
      };
      options.group = lib.mkOption {
        type = lib.types.str;
        description = "The group of the wrapper program.";
      };
      options.permissions = lib.mkOption {
        type = fileModeType;
        default = "u+rx,g+x,o+x";
        example = "a+rx";
        description = ''
          The permissions of the wrapper program. The format is that of a
          symbolic or numeric file mode understood by {command}`chmod`.
        '';
      };
      options.capabilities = lib.mkOption {
        type = lib.types.commas;
        default = "";
        description = ''
          A comma-separated list of capability clauses to be given to the
          wrapper program. The format for capability clauses is described in the
          “TEXTUAL REPRESENTATION” section of the {manpage}`cap_from_text(3)`
          manual page. For a list of capabilities supported by the system, check
          the {manpage}`capabilities(7)` manual page.

          ::: {.note}
          `cap_setpcap`, which is required for the wrapper
          program to be able to raise caps into the Ambient set is NOT raised
          to the Ambient set so that the real program cannot modify its own
          capabilities!! This may be too restrictive for cases in which the
          real program needs cap_setpcap but it at least leans on the side
          security paranoid vs. too relaxed.
          :::
        '';
      };
      options.setuid = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to add the setuid bit the wrapper program.";
      };
      options.setgid = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to add the setgid bit the wrapper program.";
      };
    }
  );

  ###### Activation script for the setcap wrappers
  mkSetcapPerms =
    {
      program,
      capabilities,
      source,
      owner,
      group,
      permissions,
      ...
    }:
    # TODO: implement. I'm not sure if nix2container supports this, may require
    # upstream contributions.
    throw "Not implemented :(";

  mkSetuidPerms =
    {
      program,
      source,
      owner,
      group,
      setuid,
      setgid,
      permissions,
      ...
    }:
    let
      toId =
        x: y: v:
        if lib.hasPrefix "+" v then lib.toIntBase10 (lib.substring 1 (-1) v) else x.${v}.${y};
    in
    {
      package = config.security.wrapperPackage;
      file = "${config.security.wrapperDir}/${program}";
      uid = toId config.users.users "uid" owner;
      gid = toId config.users.groups "gid" group;
      mode = builtins.readFile (
        pkgs.runCommandLocal "mode2octal" { } ''
          ${lib.getExe mode2octal} u${if setuid then "+" else "-"}s,g${if setgid then "+" else "-"}s,${permissions} > $out
        ''
      );
    };

  mkWrapperPackage = pkgs.runCommandLocal "wrappers" { } (
    lib.concatStringsSep "\n" (
      [
        ''
          mkdir -p $out${config.security.wrapperDir}
        ''
      ]
      ++ (builtins.map (
        { program, source, ... }:
        ''
          cp ${securityWrapper source}/bin/security-wrapper "$out${config.security.wrapperDir}/${program}"
        ''
      ) (lib.attrValues wrappers))
    )
  );

  mkWrapperPerms = builtins.map (
    opts: if opts.capabilities != "" then mkSetcapPerms opts else mkSetuidPerms opts
  ) (lib.attrValues wrappers);
in
{
  imports = [
    (lib.mkRemovedOptionModule [ "security" "setuidOwners" ] "Use security.wrappers instead")
    (lib.mkRemovedOptionModule [ "security" "setuidPrograms" ] "Use security.wrappers instead")
  ];

  ###### interface

  options = {
    security.enableWrappers = lib.mkEnableOption "SUID/SGID wrappers" // {
      default = true;
    };

    security.wrappers = lib.mkOption {
      type = lib.types.attrsOf wrapperType;
      default = { };
      example = lib.literalExpression ''
        {
          # a setuid root program
          doas =
            { setuid = true;
              owner = "root";
              group = "root";
              source = "''${pkgs.doas}/bin/doas";
            };

          # a setgid program
          locate =
            { setgid = true;
              owner = "root";
              group = "mlocate";
              source = "''${pkgs.locate}/bin/locate";
            };

          # a program with the CAP_NET_RAW capability
          ping =
            { owner = "root";
              group = "root";
              capabilities = "cap_net_raw+ep";
              source = "''${pkgs.iputils.out}/bin/ping";
            };
        }
      '';
      description = ''
        This option effectively allows adding setuid/setgid bits, capabilities,
        changing file ownership and permissions of a program without directly
        modifying it. This works by creating a wrapper program in a directory
        (not configurable), which is then added to the shell `PATH`.
      '';
    };

    security.wrapperDir = lib.mkOption {
      type = lib.types.path;
      default = "/run/wrappers/bin";
      internal = true;
      description = ''
        This option defines the path to the wrapper programs. It
        should not be overridden.
      '';
    };

    security.wrapperPackage = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
    };
  };

  ###### implementation
  config = lib.mkIf config.security.enableWrappers {

    assertions = lib.mapAttrsToList (name: opts: {
      assertion = opts.setuid || opts.setgid -> opts.capabilities == "";
      message = ''
        The security.wrappers.${name} wrapper is not valid:
            setuid/setgid and capabilities are mutually exclusive.
      '';
    }) wrappers;

    security.wrappers =
      let
        mkSetuidRoot = source: {
          setuid = true;
          owner = "root";
          group = "root";
          inherit source;
        };
      in
      {
        # These are mount related wrappers that require the +s permission.
        fusermount = mkSetuidRoot "${lib.getBin pkgs.fuse}/bin/fusermount";
        fusermount3 = mkSetuidRoot "${lib.getBin pkgs.fuse3}/bin/fusermount3";
        mount = mkSetuidRoot "${lib.getBin pkgs.util-linux}/bin/mount";
        umount = mkSetuidRoot "${lib.getBin pkgs.util-linux}/bin/umount";
      };

    security.wrapperPackage = lib.mkIf config.security.enableWrappers mkWrapperPackage;
    system.build.perms = if config.security.enableWrappers then mkWrapperPerms else [ ];

    # Add wrappers to PATH
    environment.variables.PATH = lib.optional config.security.enableWrappers config.security.wrapperDir;
  };
}
