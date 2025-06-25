{
  config,
  lib,
  pkgs,
  ...
}:
let
  etc' = lib.filter (f: f.enable) (lib.attrValues config.environment.etc);
  etc = pkgs.runCommandNoCCLocal "etc" { } ''
    set -euo pipefail
    first=1
    makeEtcEntry() {
      src="$1"
      target="$2"
      mode="$3"
      user="$4"
      group="$5"

      if [[ "$src" = *'*'* ]]; then
        # If the source name contains '*', perform globbing.
        mkdir -p "$out/etc/$target"
        for fn in $src; do
          if [ "$mode" != symlink ]; then
            cp "$fn" "$out/etc/$target/"
          else
            ln -s "$fn" "$out/etc/$target/"
          fi
        done
      else

        mkdir -p "$out/etc/$(dirname "$target")"
        if ! [ -e "$out/etc/$target" ]; then
          if [ "$mode" != symlink ]; then
            cp "$src" "$out/etc/$target"
          else
            ln -s "$src" "$out/etc/$target"
          fi
        else
          echo "duplicate entry $target -> $src"
          if [ "$(readlink "$out/etc/$target")" != "$src" ]; then
            echo "mismatched duplicate entry $(readlink "$out/etc/$target") <-> $src"
            ret=1

            continue
          fi
        fi

        if [ "$mode" != symlink ]; then
          # Don't save metadata to /etc as upstream does, save it to JSON which
          # we can import from Nix for further processing.
          if [[ "$first" = "1" ]]; then
            first=0
          else
            echo -n "," >> "$out/attrs.json"
          fi

          echo -n "\"$(echo "/etc/$target" | sed 's|"|\\"|g')\":{" >> "$out/attrs.json"
          echo -n "\"mode\":\"$mode\"," >> "$out/attrs.json"
          echo -n "\"user\":\"$user\"," >> "$out/attrs.json"
          echo -n "\"group\":\"$group\"" >> "$out/attrs.json"
          echo -n "}" >> "$out/attrs.json"
        fi
      fi
    }

    mkdir -p "$out/etc"
    echo -n "{" >> "$out/attrs.json"

    ${lib.concatMapStringsSep "\n" (
      etcEntry:
      lib.escapeShellArgs [
        "makeEtcEntry"
        # Force local source paths to be added to the store
        "${etcEntry.source}"
        etcEntry.target
        etcEntry.mode
        etcEntry.user
        etcEntry.group
      ]
    ) etc'}

    echo -n "}" >> "$out/attrs.json"
  '';
  etcMerged = pkgs.runCommandNoCCLocal "etc-merged" { } ''
    copyAll() {
      while IFS= read -rd "" f; do
        rel="$(realpath --no-symlinks --relative-to="$1" "$f")"
        if [[ "$rel" = '.' ]]; then
          dst="$out$2"
        else
          dst="$out$2/$rel"
        fi
        if [ -d "$f" ]; then
          [ -d "$dst" ] || mkdir "$dst"
        else
          if [ -e "$dst" ]; then
            echo "duplicated file $f -> $dst" >&2
            exit 1
          fi
          cp -P "$f" "$dst"
        fi
      done
    }

    mkdir -p $out/etc
    find "${etc}/etc" -print0 | copyAll "${etc}/etc" /etc
    find "${config.system.path}/etc" -print0 | copyAll "${config.system.path}/etc" /etc
  '';
in
{
  options = {
    environment.etc = lib.mkOption {
      default = { };
      example = lib.literalExpression ''
        { example-configuration-file =
            { source = "/nix/store/.../etc/dir/file.conf.example";
              mode = "0440";
            };
          "default/useradd".text = "GROUP=100 ...";
        }
      '';
      description = ''
        Set of files that have to be linked in {file}`/etc`.
      '';

      type =
        with lib.types;
        attrsOf (
          submodule (
            {
              name,
              config,
              options,
              ...
            }:
            {
              options = {

                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = ''
                    Whether this /etc file should be generated.  This
                    option allows specific /etc files to be disabled.
                  '';
                };

                target = lib.mkOption {
                  type = lib.types.str;
                  description = ''
                    Name of symlink (relative to
                    {file}`/etc`).  Defaults to the attribute
                    name.
                  '';
                };

                text = lib.mkOption {
                  default = null;
                  type = lib.types.nullOr lib.types.lines;
                  description = "Text of the file.";
                };

                source = lib.mkOption {
                  type = lib.types.path;
                  description = "Path of the source file.";
                };

                mode = lib.mkOption {
                  type = lib.types.str;
                  default = "symlink";
                  example = "0600";
                  description = ''
                    If set to something else than `symlink`,
                    the file is copied instead of symlinked, with the given
                    file mode.
                  '';
                };

                uid = lib.mkOption {
                  default = 0;
                  type = lib.types.int;
                  description = ''
                    UID of created file. Only takes effect when the file is
                    copied (that is, the mode is not 'symlink').
                  '';
                };

                gid = lib.mkOption {
                  default = 0;
                  type = lib.types.int;
                  description = ''
                    GID of created file. Only takes effect when the file is
                    copied (that is, the mode is not 'symlink').
                  '';
                };

                user = lib.mkOption {
                  default = "+${toString config.uid}";
                  type = lib.types.str;
                  description = ''
                    User name of file owner.

                    Only takes effect when the file is copied (that is, the
                    mode is not `symlink`).

                    When `services.userborn.enable`, this option has no effect.
                    You have to assign a `uid` instead. Otherwise this option
                    takes precedence over `uid`.
                  '';
                };

                group = lib.mkOption {
                  default = "+${toString config.gid}";
                  type = lib.types.str;
                  description = ''
                    Group name of file owner.

                    Only takes effect when the file is copied (that is, the
                    mode is not `symlink`).

                    When `services.userborn.enable`, this option has no effect.
                    You have to assign a `gid` instead. Otherwise this option
                    takes precedence over `gid`.
                  '';
                };

              };

              config = {
                target = lib.mkDefault name;
                source = lib.mkIf (config.text != null) (
                  let
                    name' = "etc-" + lib.replaceStrings [ "/" ] [ "-" ] name;
                  in
                  lib.mkDerivedConfig options.text (pkgs.writeText name')
                );
              };

            }
          )
        );
    };
  };

  config = {
    system.build.etc = etcMerged;
    # FIXME: use generated attrs.json, required to correctly handle globbing.
    system.build.perms =
      let
        toId =
          x: y: v:
          if lib.hasPrefix "+" v then lib.toIntBase10 (lib.substring 1 (-1) v) else x.${v}.${y};
      in
      lib.foldl' (
        acc: entry:
        acc
        ++ [
          {
            inherit (entry) mode;
            package = config.system.build.etc;
            file = "/etc/${entry.target}";
            uid = toId config.users.users "uid" entry.user;
            gid = toId config.users.groups "gid" entry.group;
          }
        ]
      ) [ ] (lib.filter (f: f.mode != "symlink") etc');
  };
}
