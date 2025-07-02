{
  config,
  lib,
  utils,
  pkgs,
  ...
}:

let
  inherit (lib)
    attrNames
    attrValues
    concatStringsSep
    concatMapStringsSep
    elem
    filterAttrs
    flatten
    flip
    foldr
    getAttr
    hasAttr
    listToAttrs
    literalExpression
    mapAttrsToList
    mkDefault
    mkIf
    mkMerge
    mkOption
    stringLength
    trace
    types
    xor
    ;

  ids = config.ids;
  cfg = config.users;

  userOpts =
    { name, config, ... }:
    {

      options = {

        enable = mkOption {
          type = types.bool;
          default = true;
          example = false;
          description = ''
            If set to false, the user account will not be created. This is useful for when you wish to conditionally
            disable user accounts.
          '';
        };

        name = mkOption {
          type = types.passwdEntry types.str;
          apply =
            x:
            assert (
              stringLength x < 32 || abort "Username '${x}' is longer than 31 characters which is not allowed!"
            );
            x;
          description = ''
            The name of the user account. If undefined, the name of the
            attribute set will be used.
          '';
        };

        description = mkOption {
          type = types.passwdEntry types.str;
          default = "";
          example = "Alice Q. User";
          description = ''
            A short description of the user account, typically the
            user's full name.  This is actually the “GECOS” or “comment”
            field in {file}`/etc/passwd`.
          '';
        };

        uid = mkOption {
          type = types.int;
          description = ''
            The account UID.
          '';
        };

        isSystemUser = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Indicates if the user is a system user or not. This option
            only has an effect if {option}`uid` is
            {option}`null`, in which case it determines whether
            the user's UID is allocated in the range for system users
            (below 1000) or in the range for normal users (starting at
            1000).
            Exactly one of `isNormalUser` and
            `isSystemUser` must be true.
          '';
        };

        isNormalUser = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Indicates whether this is an account for a “real” user.
            This automatically sets {option}`group` to `users`,
            {option}`createHome` to `true`,
            {option}`home` to {file}`/home/«username»`,
            {option}`useDefaultShell` to `true`,
            and {option}`isSystemUser` to `false`.
            Exactly one of `isNormalUser` and `isSystemUser` must be true.
          '';
        };

        group = mkOption {
          type = types.nonEmptyStr;
          apply =
            x:
            assert (
              stringLength x < 32 || abort "Group name '${x}' is longer than 31 characters which is not allowed!"
            );
            x;
          description = "The user's primary group.";
        };

        extraGroups = mkOption {
          type = types.listOf types.nonEmptyStr;
          default = [ ];
          description = "The user's auxiliary groups.";
        };

        home = mkOption {
          type = types.passwdEntry types.path;
          default = "/var/empty";
          description = "The user's home directory.";
        };

        homeMode = mkOption {
          type = types.strMatching "[0-7]{1,5}";
          default = "700";
          description = "The user's home directory mode in numeric format. See {manpage}`chmod(1)`. The mode is only applied if {option}`users.users.<name>.createHome` is true.";
        };

        shell = mkOption {
          type = types.nullOr (types.either types.shellPackage (types.passwdEntry types.path));
          default = pkgs.shadow;
          defaultText = literalExpression "pkgs.shadow";
          example = literalExpression "pkgs.bashInteractive";
          description = ''
            The path to the user's shell. Can use shell derivations,
            like `pkgs.bashInteractive`. Don’t
            forget to enable your shell in
            `programs` if necessary,
            like `programs.zsh.enable = true;`.
          '';
        };

        createHome = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether to create the home directory and ensure ownership as well as
            permissions to match the user.
          '';
        };

        useDefaultShell = mkOption {
          type = types.bool;
          default = false;
          description = ''
            If true, the user's shell will be set to
            {option}`users.defaultUserShell`.
          '';
        };
      };

      config = mkMerge [
        {
          name = mkDefault name;
          shell = mkIf config.useDefaultShell (mkDefault cfg.defaultUserShell);
        }
        (mkIf config.isNormalUser {
          group = mkDefault "users";
          createHome = mkDefault true;
          home = mkDefault "/home/${config.name}";
          homeMode = mkDefault "700";
          useDefaultShell = mkDefault true;
          isSystemUser = mkDefault false;
        })
      ];
    };

  groupOpts =
    { name, config, ... }:
    {

      options = {

        name = mkOption {
          type = types.passwdEntry types.str;
          description = ''
            The name of the group. If undefined, the name of the attribute set
            will be used.
          '';
        };

        gid = mkOption {
          type = with types; nullOr int;
          default = null;
          description = ''
            The group GID. If the GID is null, a free GID is picked on
            activation.
          '';
        };

        members = mkOption {
          type = with types; listOf (passwdEntry str);
          default = [ ];
          description = ''
            The user names of the group members, added to the
            `/etc/group` file.
          '';
        };

      };

      config = {
        name = mkDefault name;

        members = mapAttrsToList (n: u: u.name) (
          filterAttrs (n: u: elem config.name u.extraGroups) cfg.users
        );
      };

    };

  idsAreUnique =
    set: idAttr:
    !(foldr
      (
        name:
        args@{ dup, acc }:
        let
          id = toString (getAttr idAttr (getAttr name set));
          exists = hasAttr id acc;
          newAcc =
            acc
            // (listToAttrs [
              {
                name = id;
                value = true;
              }
            ]);
        in
        if dup then
          args
        else if exists then
          trace "Duplicate ${idAttr} ${id}" {
            dup = true;
            acc = null;
          }
        else
          {
            dup = false;
            acc = newAcc;
          }
      )
      {
        dup = false;
        acc = { };
      }
      (attrNames set)
    ).dup;

  uidsAreUnique = idsAreUnique (filterAttrs (n: u: u.uid != null) cfg.users) "uid";
  gidsAreUnique = idsAreUnique (filterAttrs (n: g: g.gid != null) cfg.groups) "gid";
  groupNames = mapAttrsToList (n: g: g.name) cfg.groups;
  usersWithoutExistingGroup = filterAttrs (n: u: u.group != "" && !elem u.group groupNames) cfg.users;
in
{
  options = {
    users.populateUnixDatabase = mkOption {
      default = true;
      example = false;
      type = types.bool;
      description = ''
        Populate user database files: /etc/passwd, /etc/group and /etc/shadow.
      '';
    };

    users.users = mkOption {
      default = { };
      type = with types; attrsOf (submodule userOpts);
      example = {
        alice = {
          uid = 1234;
          description = "Alice Q. User";
          home = "/home/alice";
          createHome = true;
          group = "users";
          extraGroups = [ "wheel" ];
          shell = "/bin/sh";
        };
      };
      description = ''
        Additional user accounts to be created during image build process.
        This can also be used to set options for root.
      '';
    };

    users.groups = mkOption {
      default = { };
      example = {
        students.gid = 1001;
        hackers.gid = 1002;
      };
      type = with types; attrsOf (submodule groupOpts);
      description = ''
        Additional groups to be created during image build process.
      '';
    };
  };

  config = {
    assertions =
      [
        {
          assertion = uidsAreUnique && gidsAreUnique;
          message = "UIDs and GIDs must be unique!";
        }
        {
          assertion = usersWithoutExistingGroup == { };
          message =
            let
              errUsers = attrNames usersWithoutExistingGroup;
            in
            ''
              The following users have a primary group that is undefined: ${concatStringsSep " " errUsers}
            '';
        }
      ]
      ++ flatten (
        flip mapAttrsToList cfg.users (
          name: user: [
            {
              assertion = builtins.match "[a-zA-Z0-9_.][a-zA-Z0-9_.-]*" user.name != null;
              message = "The username \"${user.name}\" is not valid";
            }
            {
              assertion = user.isNormalUser && user.uid != null -> user.uid >= 1000;
              message = ''
                A user cannot have a users.users.${user.name}.uid set below 1000 and set users.users.${user.name}.isNormalUser.
                Either users.users.${user.name}.isSystemUser must be set to true instead of users.users.${user.name}.isNormalUser
                or users.users.${user.name}.uid must be changed to 1000 or above.
              '';
            }
            {
              assertion =
                let
                  # we do an extra check on isNormalUser here, to not trigger this assertion when isNormalUser is set and uid to < 1000
                  isEffectivelySystemUser =
                    user.isSystemUser || (user.uid != null && user.uid < 1000 && !user.isNormalUser);
                in
                xor isEffectivelySystemUser user.isNormalUser;
              message = ''
                Exactly one of users.users.${user.name}.isSystemUser and users.users.${user.name}.isNormalUser must be set.
              '';
            }
          ]
        )
      );

    users.users = {
      root = {
        uid = ids.uids.root;
        description = "System administrator";
        home = "/root";
        shell = mkDefault cfg.defaultUserShell;
        group = "root";
      };
      nobody = {
        uid = ids.uids.nobody;
        isSystemUser = true;
        description = "Unprivileged account (don't use!)";
        group = "nogroup";
      };
    };
    users.groups = {
      root.gid = ids.gids.root;
      nogroup.gid = ids.gids.nogroup;
    };

    environment.etc = mkIf cfg.populateUnixDatabase {
      "passwd" = {
        text = concatMapStringsSep "\n" (
          u:
          let
            inherit (cfg.groups."${u.group}") gid;
            shell = utils.toShellPath u.shell;
          in
          "${u.name}:x:${builtins.toString u.uid}:${builtins.toString gid}:${u.description}:${u.home}:${shell}"
        ) (lib.filter (user: user.enable) (attrValues cfg.users));
      };
      "group" = {
        text = concatMapStringsSep "\n" (
          group: "${group.name}:x:${builtins.toString group.gid}:${concatStringsSep "," group.members}"
        ) (attrValues cfg.groups);
      };
      "shadow" = {
        text = concatMapStringsSep "\n" (user: "${user.name}:!:1::::::") (
          lib.filter (user: user.enable) (attrValues cfg.users)
        );
        mode = "0600";
      };
    };

    system.extraSystemBuilderCmds = concatMapStringsSep "\n" (user: ''
      mkdir -p "$out/${user.home}"
    '') (lib.filter (user: user.enable && user.createHome) (attrValues cfg.users));
    system.build.perms = map (user: {
      package = config.system.build.toplevel;
      file = user.home;
      uid = user.uid;
      gid = cfg.groups.${user.name}.gid;
      mode = user.homeMode;
    }) (lib.filter (user: user.enable && user.createHome) (attrValues cfg.users));
  };
}
