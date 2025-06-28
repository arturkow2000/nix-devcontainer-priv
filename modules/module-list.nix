{ upstreamModulePath }:
[
  # "${upstreamModulePath}/config/appstream.nix"
  # "${upstreamModulePath}/config/console.nix"
  # "${upstreamModulePath}/config/debug-info.nix"
  # "${upstreamModulePath}/config/fanout.nix"
  # "${upstreamModulePath}/config/fonts/fontconfig.nix"
  # "${upstreamModulePath}/config/fonts/fontdir.nix"
  # "${upstreamModulePath}/config/fonts/ghostscript.nix"
  # "${upstreamModulePath}/config/fonts/packages.nix"
  # "${upstreamModulePath}/config/gtk/gtk-icon-cache.nix"
  # "${upstreamModulePath}/config/i18n.nix"
  # "${upstreamModulePath}/config/ldap.nix"
  # "${upstreamModulePath}/config/locale.nix"
  ./config/ldso.nix
  # "${upstreamModulePath}/config/malloc.nix"
  # "${upstreamModulePath}/config/mysql.nix"
  # "${upstreamModulePath}/config/networking.nix"
  ./config/nix-channel.nix
  "${upstreamModulePath}/config/nix-flakes.nix"
  "${upstreamModulePath}/config/nix-remote-build.nix"
  "${upstreamModulePath}/config/nix.nix"
  "${upstreamModulePath}/config/nsswitch.nix"
  # "${upstreamModulePath}/config/power-management.nix"
  # "${upstreamModulePath}/config/qt.nix"
  # "${upstreamModulePath}/config/resolvconf.nix"
  ./config/shells-environment.nix
  # "${upstreamModulePath}/config/stevenblack.nix"
  # "${upstreamModulePath}/config/stub-ld.nix"
  # "${upstreamModulePath}/config/swap.nix"
  # "${upstreamModulePath}/config/sysctl.nix"
  # "${upstreamModulePath}/config/system-environment.nix"
  ./config/system-path.nix
  ./config/terminfo.nix
  "${upstreamModulePath}/config/unix-odbc-drivers.nix"
  ./config/users-groups.nix
  # "${upstreamModulePath}/config/vte.nix"
  ######################################################################
  "${upstreamModulePath}/misc/assertions.nix"
  ./misc/documentation.nix
  ./misc/extra-arguments.nix
  # TODO: actually use IDs in users module
  "${upstreamModulePath}/misc/ids.nix"
  "${upstreamModulePath}/misc/label.nix"
  "${upstreamModulePath}/misc/lib.nix"
  "${upstreamModulePath}/misc/man-db.nix"
  # Not supported.
  # "${upstreamModulePath}/misc/mandoc.nix"
  "${upstreamModulePath}/misc/meta.nix"
  "${upstreamModulePath}/misc/nixpkgs.nix"
  "${upstreamModulePath}/misc/nixpkgs-flake.nix"
  "${upstreamModulePath}/misc/passthru.nix"
  "${upstreamModulePath}/misc/version.nix"
  "${upstreamModulePath}/system/build.nix"
  ./system/top-level.nix
  ./system/container.nix
  ./system/etc.nix
  ./system/nix2container.nix
  ./system/nix-snapshotter.nix
  ./system/nix.nix
  ./programs/shadow.nix
  ./security/pam.nix
  ./security/sudo.nix
  ./security/wrappers/default.nix
  # "${upstreamModulePath}/security/sudo.nix"
  "${upstreamModulePath}/programs/bash-my-aws.nix"
  "${upstreamModulePath}/programs/bash/bash.nix"
  "${upstreamModulePath}/programs/bash/bash-completion.nix"
  "${upstreamModulePath}/programs/bash/ls-colors.nix"
  "${upstreamModulePath}/programs/bash/blesh.nix"
  "${upstreamModulePath}/programs/bash/undistract-me.nix"
  "${upstreamModulePath}/programs/bat.nix"
  "${upstreamModulePath}/programs/command-not-found/command-not-found.nix"
  "${upstreamModulePath}/programs/direnv.nix"
  # "${upstreamModulePath}/programs/environment.nix"
  "${upstreamModulePath}/programs/fish.nix"
  "${upstreamModulePath}/programs/fzf.nix"
  "${upstreamModulePath}/programs/git-worktree-switcher.nix"
  "${upstreamModulePath}/programs/git.nix"
  "${upstreamModulePath}/programs/htop.nix"
  "${upstreamModulePath}/programs/lazygit.nix"
  "${upstreamModulePath}/programs/less.nix"
  "${upstreamModulePath}/programs/nano.nix"
  "${upstreamModulePath}/programs/neovim.nix"
  ./programs/nix-ld.nix
  "${upstreamModulePath}/programs/starship.nix"
  "${upstreamModulePath}/programs/vim.nix"
  "${upstreamModulePath}/programs/xonsh.nix"
  "${upstreamModulePath}/programs/zsh/oh-my-zsh.nix"
  "${upstreamModulePath}/programs/zsh/zsh-autoenv.nix"
  "${upstreamModulePath}/programs/zsh/zsh-autosuggestions.nix"
  "${upstreamModulePath}/programs/zsh/zsh-syntax-highlighting.nix"
  ./programs/zsh/zsh.nix
  "${upstreamModulePath}/security/ca.nix"
]
