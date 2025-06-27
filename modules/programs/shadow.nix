{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.security.loginDefs;
in
{
  options = {
    security.shadow.enable = lib.mkEnableOption "" // {
      default = true;
      description = ''
        Enable the shadow authentication suite, which provides critical programs such as su, login, passwd.

        Note: This is currently experimental. Only disable this if you're
        confident that you can recover your system if it breaks.
      '';
    };

    security.loginDefs = {
      package = lib.mkPackageOption pkgs "shadow" { };
    };

    security.pam.whitelistedServices = lib.mkOption {
      default = [ ];
      description = ''
        List of allowed PAM services. Only shadow services and services listed
        here are allowed.
      '';
      type = with lib.types; listOf nonEmptyStr;
    };

    users.defaultUserShell = lib.mkOption {
      description = ''
        This option defines the default shell assigned to user
        accounts. This can be either a full system path or a shell package.

        This must not be a store path, since the path is
        used outside the store (in particular in /etc/passwd).
      '';
      example = lib.literalExpression "pkgs.zsh";
      type = lib.types.either lib.types.path lib.types.shellPackage;
    };
  };

  config = lib.mkIf config.security.shadow.enable {
    environment.systemPackages = [
      cfg.package
    ];
    environment.etc =
      {
        "pam.d/chfn".source = "${cfg.package}/etc/pam.d/chfn";
        "pam.d/chpasswd".source = "${cfg.package}/etc/pam.d/chpasswd";
        "pam.d/chsh".source = "${cfg.package}/etc/pam.d/chsh";
        "pam.d/groupmems".source = "${cfg.package}/etc/pam.d/groupmems";
        "pam.d/login".source = "${cfg.package}/etc/pam.d/login";
        "pam.d/newusers".source = "${cfg.package}/etc/pam.d/newusers";
        "pam.d/passwd".source = "${cfg.package}/etc/pam.d/passwd";
        "pam.d/su".source = "${cfg.package}/etc/pam.d/su";
        # Deny any unknown services from using PAM.
        "pam.d/other".text = ''
          auth required pam_deny.so
          account required pam_deny.so
          password required pam_deny.so
          session required pam_deny.so
        '';
        "pam.d/system-auth".text = ''
          #%PAM-1.0
          auth required pam_unix.so try_first_pass nullok
          auth optional pam_permit.so

          account required pam_unix.so
          account optional pam_permit.so

          password required pam_unix.so try_first_pass nullok shadow yescrypt
          password optional pam_permit.so

          session required pam_unix.so
          session optional pam_permit.so
        '';
      }
      // (lib.foldr (
        x: acc:
        acc
        // {
          "pam.d/${x}".text = ''
            auth include system-auth
            account include system-auth
            password include system-auth
            session include system-auth
          '';
        }
      ) { } config.security.pam.whitelistedServices);

    security.wrappers = {
      unix_chkpwd = {
        setuid = true;
        owner = "root";
        group = "root";
        source = "${config.security.pam.package}/bin/unix_chkpwd";
      };
    };
  };
}
