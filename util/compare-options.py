from argparse import ArgumentParser
from json import load
import re
import sys
import hashlib

# Options, present in NixOS but not supported in devcontainer.
# Some will never be supported because they don't apply to containers, e.g. boot or kernel-related options.
# Some will probably never be supported, e.g. systemd, services. While possible to run in containers,
# not really usable from ms devcontainers.
options_filter_out = [
    # Kernel/hw related stuff, we will never support in nix-devcontainer
    r"^zramSwap\.",
    r"^power\.",
    r"^swapDevices(\..*$|$)",
    r"^powerManagement\.",
    r"^system\.etc\.overlay",
    r"^system\.boot\.",
    r"^boot\.",
    r"^console\.",
    r"^fileSystems(\..*$|$)",
    r"^programs\.xfs_quota\.",
    r"^programs\.cfs-zen-tweaks\.",
    r"^programs\.coolercontrol\.",
    r"^programs\.corectrl\.",
    r"^programs\.corefreq\.",
    r"^programs\.tuxclocker\.",
    r"^programs\.cpu-energy-meter\.",
    r"^programs\.udevil\.",
    r"^programs\.streamcontroller\.",
    r"^programs\.flashprog\.",  # udev rules
    r"^programs\.weylus\.",  # for using phone/tablet as touchscreen
    r"^programs\.droidcam\.",
    r"^programs\.kbdlight\.",  # for controlling kbd backlight on macbooks
    r"^programs\.rog-control-center\.",
    r"^programs\.ryzen-monitor-ng\.",
    r"^programs\.yubikey-manager\.",
    r"^programs\.yubikey-touch-detector\.",
    r"^programs\.mdevctl\.",  # mediated devices stuff
    r"^programs\.immersed(\.|-vr$)",  # vr stuff
    r"^programs\.k40-whisperer\.",  # for controlling laser cutters
    r"^programs\.bazecor\.",  # programmable keyboards
    r"^programs\.bcc\.",  # BPF-based
    r"^programs\.chrysalis\.",  # another keyboards
    r"^programs\.digitalbitbox\.",
    r"^programs\.dmrconfig\.",
    r"^programs\.nix-required-mounts\.",
    r"^programs\.soundmodem\.",
    r"^programs\.qgroundcontrol\.",  # drone control
    r"^programs\.ns-usbloader\.",
    r"^programs\.projecteur\.",
    r"^programs\.quark-goldleaf\.",
    r"^programs\.sedutil\.",
    r"^programs\.xppen\.",
    r"^programs\.solaar\.",
    r"^programs\.entropy\.",
    r"^programs\.idescriptor\.",
    r"^programs\.librepods\.",
    r"^programs\.nvrs\.",
    r"^programs\.pmount\.",
    r"^ec2\.",
    r"^nixops\.enableDeprecatedAutoLuks",
    # Mostly unusable, but does have some things we may want, e.g. printer drivers, other usermode drivers, for e.g. logic analyzers, JTAG/SWD debuggers, etc.
    r"^hardware\.",
    # Not configurable here, networking is controlled by OCI runtime, not us.
    r"^networking\.",
    r"^nix\.firewall\.",
    r"^environment\.wvdial\.",
    # Possible, but rarely used in containers, systemd depends on many kernel interfaces typically not
    # available in containers so requires privileged containers (not necessarily --privileged flag,
    # specific capabilities may be added using --cap-add).
    r"^systemd\.",
    r"^services\.",
    r"^system\.services$",
    # Not supported, cache is always generated at build time.
    r"^documentation\.man\.cache\.generateAtRuntime$",
    # Things related to all sorts virtualization: VMs (KVM, Xen), containerization (Docker, containerD).
    # Typically not used from devcontainers. Dependent on kernel (privileged containers) and systemd.
    r"^virtualisation\.",
    r"^containers(\..*$|$)",
    r"^openstack\.",
    r"^programs\.virt-manager\.",
    r"^programs\.singularity\.",
    r"^programs\.criu\.",
    r"^programs\.kubeswitch\.",  # k8s related
    r"^programs\.schroot\.",
    r"^programs\.extra-container\.",
    # Security related options, mostly unsupported (strong kernel dependency, niche uses in container which is already sandboxed), except
    # for nixos setuid/setcap wrappers (we have custom wrapper implementation that works in containers),
    # and sudo - typically we run as non-root in the container, e.g. vscode user, but we want easy to access to root.
    r"^security\.acme\.",
    r"^security\.agnos\.",
    r"^security\.allowSimultaneousMultithreading$",
    r"^security\.allowUserNamespaces$",
    r"^security\.apparmor\.",
    r"^security\.auditd?\.",
    r"^security\.chromiumSuidSandbox\.",
    r"^security\.account-utils\.",
    r"^security\.run0\.",  # an alternative to sudo, depends on systemd and polkit, so not usable by us.
    # TODO: we could use this instead of standard sudo?
    # probably most devcontainer users use sudo only passwordless escalation from vscode to root user and don't thousands of weird sudo features,
    # so we could just something simpler, and get rid of PAM too (it's mostly broken anyway).
    r"^security\.doas\.",
    r"^security\.duosec\.",
    r"^security\.forcePageTableIsolation$",
    r"^security\.googleOsLogin\.",
    r"^security\.isolate\.",
    r"^security\.krb5\.",
    r"^security\.lockKernelModules$",
    r"^security\.ipa\.",
    r"^security\.loginDefs\.(?!package$)",
    r"^security\.lsm$",
    # Currently we support only
    # security.pam.package
    # security.pam.whitelistedServices
    r"^security\.pam\.(?!package$|whitelistedServices$)",
    r"^security\.please\.",
    r"^security\.polkit\.",
    r"^security\.protectKernelImage$",
    r"^security\.rtkit\.",
    r"^security\.soteria\.",
    r"^security\.sudo-rs\.",  # TODO: we could use this instead of standard sudo
    r"^security\.tpm2\.",
    r"^security\.virtualisation\.flushL1DataCache$",
    r"^security\.wrapperDirSize$",
    # For GUI applications, not supported.
    r"^xdg\.",
    r"^appstream\.",
    r"^qt5?\.",
    r"^fonts\.",
    r"^gtk\.",
    r"^programs\.gdk-pixbuf\.",
    # TODO: some features could be present.
    r"^i18n\.",
    # We don't support updating containers in place. To update containers should be rebuilt.
    r"^system\.nixos-init\.",
    r"^system\.activatable$",
    r"^system\.activationScripts$",
    r"^system\.build\.separateActivationScript$",
    r"^system\.userActivationScripts$",
    r"^system\.switch\.",
    r"^system\.tools\.nixos-build-vms\.enable$",
    r"^system\.tools\.nixos-enter\.enable$",
    r"^system\.tools\.nixos-generate-config\.enable$",
    r"^system\.tools\.nixos-install\.enable$",
    r"^system\.tools\.nixos-option\.enable$",
    r"^system\.tools\.nixos-rebuild\.enable$",
    r"^system\.tools\.nixos-rebuild\.enableRun0Elevation$",
    r"^system\.tools\.nixos-version\.enable$",
    r"^system\.preSwitchChecks$",
    r"^system\.autoUpgrade\.",
    r"^specialisation(\..*$|$)",
    # Depends on services (systemd). Not really usable, docker and ms devcontainers will typically bypass PAM.
    r"^users\.ldap\.",
    r"^users\.mysql\.",
    r"^users\.(users|extraUsers)\.<name>\.openssh\.",
    r"^users\.(users|extraUsers)\.<name>\.initial(Hashed)?Password$",
    # This could be supported one day if one wishes to run nested containers as non-root.
    r"^users\.(users|extraUsers)\.<name>\.sub(U|G)idRanges(\..*$|$)",
    # Would require some code to run on container init, not reliable.
    r"^users\.(users|extraUsers)\.<name>\.autoSubUidGidRange$",
    # Depends on specific kernel interfaces, not usable from standard containers.
    r"^users\.(users|extraUsers)\.<name>\.cryptHomeLuks$",
    # Not usable (PAM bypass).
    r"^users\.(users|extraUsers)\.<name>\.(linger|expires|pamMount|packages)$",
    r"^users\.manageLingering$",
    r"^users\.motd$",
    r"^users\.motdFile$",
    # Not reliable, we can't tell OCI runtime to set env vars depending on the user id we use to spawn tasks.
    r"^environment\.(local|home)BinInPath$",
    r"^environment\.sessionVariables$",
    r"^environment\.profileRelativeSessionVariables$",
    r"^programs\.rust-motd\.",
    r"^users\.allowNoPasswordLogin$",
    # Containers are immutable (always false).
    r"^users\.mutableUsers$",
    # Set by host, not us.
    r"^time\.timeZone$",
    r"^time\.hardwareClockInLocalTime$",
    r"^location\.latitude$",
    r"^location\.longitude$",
    r"^location\.provider$",
    # Desktop environments
    r"^environment\.budgie\.",
    r"^environment\.cinnamon\.",
    r"^environment\.cosmic\.",
    r"^environment\.gnome\.",
    r"^environment\.lxqt\.",
    r"^environment\.mate\.",
    r"^environment\.pantheon\.",
    r"^environment\.plasma(5|6)\.",
    r"^environment\.xfce\.",
    r"^environment\.enlightenment\.",
    # Unsupported GUI programs, wayland compositors, etc.
    r"^programs\.amnezia-vpn\.",
    r"^programs\.chromium",
    r"^programs\.google-chrome\.",
    r"^programs\.captive-browser\.",
    r"^programs\.firefox",
    r"^programs\.dwl\.",
    r"^programs\.dms-shell\.",
    r"^programs\.pinnacle\.",
    r"^programs\.mango\.",
    r"^programs\.hyprland\.",
    r"^programs\.iio-hyprland\.",
    r"^programs\.hyprlock\.",
    r"^programs\.gtklock\.",
    r"^programs\.i3lock\.",
    r"^programs\.labwc\.",
    r"^programs\.ladybird\.",
    r"^programs\.river-classic\.",
    r"^programs\.sway\.",
    r"^programs\.steam\.",
    r"^programs\.waybar\.",
    r"^programs\.wayfire\.",
    r"^programs\.niri\.",
    r"^programs\.wayland\.miracle-wm\.",
    r"^programs\.zoom-us\.",
    r"^programs\.xwayland\.",  # Host handles Xwayland
    r"^programs\.xfconf\.",
    r"^programs\.thunar\.",
    r"^programs\.thunderbird\.",
    r"^programs\.opengamepadui\.",
    r"^programs\.partition-manager\.",
    r"^programs\.kde-pim\.",
    r"^programs\.kdeconnect\.",
    r"^programs\.gnome-disks\.",
    r"^programs\.gnome-terminal\.",
    r"^programs\.ghidra\.",
    r"^programs\.foot\.",
    r"^programs\.alvr\.",
    r"^programs\.moonlight-qt\.",
    r"^programs\._1password-gui\.",
    r"^programs\._1password\.",
    r"^programs\.wireshark\.",
    r"^programs\.streamdeck-ui\.",
    r"^programs\.obs-studio\.",
    r"^programs\.evolution\.",
    r"^programs\.evince\.",
    r"^programs\.gpu-screen-recorder\.",
    r"^programs\.geary\.",
    r"^programs\.gphoto2\.",
    r"^programs\.gpaste\.",
    r"^programs\.winbox\.",
    r"^programs\.miriway\.",
    r"^programs\.ydotool\.",
    r"^programs\.wshowkeys\.",
    r"^programs\.xss-lock\.",
    r"^programs\.slock\.",
    r"^programs\.browserpass\.",
    r"^programs\.nm-applet\.",
    r"^programs\.nautilus-open-any-terminal\.",
    r"^programs\.calls\.",
    r"^programs\.fcast-receiver\.",
    r"^programs\.k3b\.",
    r"^programs\.kclock\.",
    r"^programs\.mouse-actions\.",
    r"^programs\.pulseview\.",
    r"^programs\.seahorse\.",
    r"^programs\.plotinus\.",  # gtk3 plugin
    r"^programs\.qdmr\.",
    r"^programs\.xastir\.",
    r"^programs\.system-config-printer\.",  # graphical stuff for cups
    r"^programs\.turbovnc\.",
    r"^programs\.vscode\.",
    r"^programs\.wayvnc\.",
    r"^programs\.xscreensaver\.",
    r"^programs\.throne\.",
    r"^programs\.noctalia\.",
    r"^programs\.umbriel\.",
    r"^programs\.vellum\.",
    r"^programs\.passless\.",
    r"^programs\.ioquake3\.",
    # Could be supported (without binfmt ofc).
    r"^programs\.appimage\.",
    # Requires services (systemd)
    r"^programs\.nncp\.",
    r"^programs\.dconf\.",
    r"^programs\.gamemode\.",
    r"^programs\.gamescope\.",
    r"^programs\.ssh\.",
    r"^programs\.oddjobd\.",
    r"^programs\.feedbackd\.",
    r"^programs\.msmtp\.",
    r"^programs\.uwsm\.",  # integration of wayland compositors with systemd
    r"^programs\.ausweisapp\.",
    r"^programs\.direnv\.angrr\.",
    r"^programs\.mosh\.",  # mobile shell. probably could without services, but unlikely anyone wants this
    # vscode will typically forward gpg from the host. We need client, so we keep programs.gnupg.package.
    r"^programs\.gnupg\.agent\.",
    r"^programs\.gnupg\.dirmngr\.",
    # Typically not usable from container (requires special capabilities).
    r"^programs\.firejail\.",
    r"^programs\.jai-jail\.",
    r"^programs\.openvpn3\.",
    r"^programs\.proxychains\.",
    r"^programs\.appgate-sdp\.",
    # What tf even is that?
    r"^programs\.clash-verge\.",
    r"^programs\.tsmClient\.",
    r"^programs\.hamster\.",
    r"^programs\.cdemu\.",
    r"^programs\.envision\.",
    r"^programs\.flexoptix-app\.",
    r"^programs\.haguichi\.",
    r"^programs\.joycond-cemuhook\.",
    r"^programs\.mepo\.",
    r"^programs\.mininet\.",
    r"^programs\.minipro\.",
    r"^programs\.rush\.",  # Restricted User Shell, unlikely anyone wants this in container
    r"^programs\.nxdumpclient\.",
    r"^programs\.nixbit\.",
    # Some nix-related tools, could be supported if we support temporary installation of temporary programs in Nix container.
    r"^programs\.nix-index\.",  # good for integration with command-not-found
    r"^programs\.nh\.",  # some nix cli helper
    # TODO: we want at least some of them
    r"^programs\.television\.",
    r"^programs\.tmux\.",
    r"^programs\.screen\.",
    r"^programs\.npm\.",
    r"^programs\.java\.",
    r"^programs\.flashrom\.",
    r"^programs\.iay\.",
    r"^programs\.ccache\.",
    r"^programs\.atop\.",
    r"^programs\.zoxide\.",
    r"^programs\.yazi\.",  # some tui file manager
    r"^programs\.vivid\.",  # LS_COLORS configuration
    r"^programs\.skim\.",  # fuzzy finder
    r"^programs\.arp-scan\.",
    r"^programs\.autoenv\.",
    r"^programs\.autojump\.",  # another smart cd, seems like zoxide?
    r"^programs\.bandwhich\.",
    r"^programs\.benchexec\.",  # some tools for benchmarking
    r"^programs\.pay-respects\.",  # something for recording terminal history
    r"^programs\.nbd\.",  # Network Block Device, we can't enable NBD device (host needs to pass it on to us), but we can install tools.
    r"^programs\.sysdig\.",
    r"^programs\.systemtap\.",
    r"^programs\.sharing\.",
    r"^programs\.atuin\.",  # looks cool, probably could be made working, but requires a bit different approach to get daemon running than standard NixOS
    r"^programs\.comma\.",  # some plugin? for command-not-found
    r"^programs\.tack\.",
    r"^programs\.dsearch\.",
    r"^programs\.ente-auth\.",
    # Some network diagnostic tools we may want to support. Shouldn't require much, except for setuid/setcap.
    r"^programs\.cnping\.",
    r"^programs\.dublin-traceroute\.",
    r"^programs\.iftop\.",
    r"^programs\.iotop\.",
    r"^programs\.liboping\.",
    r"^programs\.localsend\.",
    r"^programs\.mtr\.",
    r"^programs\.nethoscope\.",
    r"^programs\.nexttrace\.",
    r"^programs\.noisetorch\.",
    r"^programs\.traceroute\.",
    r"^programs\.tcpdump\.",
    r"^programs\.usbtop\.",
    r"^programs\.sniffnet\.",
    r"^programs\.trippy\.",
    r"^programs\.wavemon\.",
    r"^programs\.zmap\.",
    r"^programs\.whois\.",
    # TODO: basic stuff, we do want these
    r"^programs\.nushell\.",
    r"^programs\.bash\.vteIntegration$",
    r"^programs\.zsh\.vteIntegration$",
    r"^security\.shadow\.su\.package$",
    r"^programs\.fuse\.",
    r"^programs\.gnupg\.package$",
    r"^documentation\.man\.mandoc\.",
    r"^documentation\.nixos\.",
    # Daemon is not supported (nix can work without one, but even that isn't fully supported).
    r"^nix\.daemon\.",
    r"^nix\.daemon(User|Group)$",
    r"^nix\.daemonCPUSchedPolicy$",
    r"^nix\.daemonIOSchedClass$",
    r"^nix\.daemonIOSchedPriority$",
    # Maybe possible without daemon but not really needed, rebuilding container clears everything.
    r"^nix\.gc\.",
    r"^nix\.optimise\.",
    r"^nix\.nrBuildUsers$",
    r"^nix\.sshServe\.",
    # Not usable without working nix.
    r"^environment\.profiles$",
    r"^environment\.profileRelativeEnvVars$",
    # TODO: unify users config interface between NixOS and nix-devcontainer where possible.
    r"^users\.enforceIdUniqueness$",
    r"^users\.extraGroups(\..*$|$)",
    r"^users\.extraUsers(\..*$|$)",
    r"^users\.users\.<name>\.hashedPassword(File$|$)",
    r"^users\.users\.<name>\.ignoreShellProgramCheck$",
    r"^users\.users\.<name>\.password(File$|$)",
    r"^users\.defaultUserHome$",
    # TODO: other things we may, or may not want.
    r"^environment\.checkConfigurationOptions$",
    r"^environment\.enableDebugInfo$",
    r"^environment\.freetds$",
    r"^environment\.memoryAllocator\.provider$",
    r"^environment\.stub-ld\.enable$",
    r"^environment\.wordlist\.",
    r"^environment\.corePackages$",
    r"^environment\.debuginfodServers$",
    r"^image\.modules$",
    r"^system\.build\.images$",
    r"^system\.build\.noFacter$",
    r"^system\.checks$",
    r"^system\.copySystemConfiguration$",
    r"^system\.extraDependencies$",
    r"^system\.forbiddenDependenciesRegex(es$|$)",
    r"^system\.includeBuildDependencies$",
    r"^system\.name$",
    r"^programs\.compsize\.",  # tool for btrfs
    r"^programs\.btrfs-heatmap\.",
    # IIRC, on NixOS this was implemented by bind-mounting at runtime. Could be done in containers
    # but needs to be done statically at image level. Probably not compatible with nix-snapshotter.
    r"^system\.replaceDependencies\.",
    # 3rd party variant of nix, interestingly has some support in nixos
    # https://lix.systems/
    r"^lix\.",
]
options_filter_out_compiled = [re.compile(r) for r in options_filter_out]

# Options that we know are not part of NixOS, but we want them specifically in nix-devcontainer.
options_downstream_only = [
    r"^build\.requiredPackages$",
    r"^security\.pam\.whitelistedServices$",
    r"^security\.wrapperPackage$",
    r"^system\.build\.layers$",
    r"^system\.build\.nix-snapshotter(\..*$|$)",
    r"^system\.build\.nix2container(\..*$|$)",
    r"^system\.build\.perms(\..*$|$)",
    r"^system\.nixos\.containerMaxLayers$",
    r"^system\.nixos\.containerName$",
    r"^system\.nixos\.nixStore(Uid|Gid)$",
    r"^users\.populateUnixDatabase$",
]
options_downstream_only_compiled = [re.compile(r) for r in options_downstream_only]


def options_compare(
    opt_name: str, opt_devcontainer: dict, opt_nixos: dict, **kwargs
) -> dict:
    differences = {}

    ignore_default = kwargs.get("ignore_default", False)
    if not ignore_default and opt_devcontainer.get("default", {}) != opt_nixos.get(
        "default", {}
    ):
        differences["default"] = [
            opt_devcontainer.get("default", {}),
            opt_nixos.get("default", {}),
        ]

    def md5(data):
        if isinstance(data, str):
            data = data.encode()
        elif data is None:
            return None
        return hashlib.md5(data).hexdigest()

    if "expected_nixos_description_md5" in kwargs:
        actual_nixos_description_md5 = md5(opt_nixos.get("description", ""))
        if actual_nixos_description_md5 != kwargs["expected_nixos_description_md5"]:
            differences["description"] = [
                actual_nixos_description_md5,
                kwargs["expected_nixos_description_md5"],
            ]
    else:
        expected_description_md5 = md5(opt_nixos.get("description", ""))
        actual_description_md5 = md5(opt_devcontainer.get("description", ""))
        if actual_description_md5 != expected_description_md5:
            differences["description"] = [
                actual_description_md5,
                expected_description_md5,
            ]

    if opt_devcontainer.get("readOnly", False) != opt_nixos.get("readOnly", False):
        differences["readOnly"] = [
            opt_devcontainer.get("readOnly", False),
            opt_nixos.get("readOnly", False),
        ]

    if "expected_nixos_type" in kwargs:
        actual_nixos_type = opt_nixos["type"]
        if actual_nixos_type != kwargs["expected_nixos_type"]:
            differences["type"] = [actual_nixos_type, kwargs["expected_nixos_type"]]
    else:
        if opt_devcontainer["type"] != opt_nixos["type"]:
            differences["type"] = [opt_devcontainer["type"], opt_nixos["type"]]

    return differences


def main():
    parser = ArgumentParser()
    parser.add_argument("nixos")
    parser.add_argument("devcontainer")
    args = parser.parse_args()

    nixos = load(open(args.nixos, "r"))
    devcontainer = load(open(args.devcontainer, "r"))

    # For detecting regexes that no longer match any options in upstream NixOS (so we know we may remove them from the list).
    regex_good_or_bad = [False] * len(options_filter_out_compiled)

    # New options added to NixOS, not present in devcontainer.
    new_upstream_options = []
    # Options added to nix-devcontainer, not present in NixOS.
    new_downstream_options = []
    # Options that definitions differ, e.g. changed type, defaults, description, etc.
    differing_options = {}
    downstream_filtered_out = []

    # Pass 1. Find options that have been added to upstream NixOS but are not present in nix-devcontainer.
    for k in nixos:
        # Filter-out we don't support.
        filtered = False
        for i, r in enumerate(options_filter_out_compiled):
            if r.match(k) is not None:
                regex_good_or_bad[i] = True
                filtered = True
                break
        if filtered:
            continue

        if not k in devcontainer:
            new_upstream_options.append(k)

    # Pass 2. Find options that have been added to nix-devcontainer but are not present in NixOS.
    for k in devcontainer:
        filtered = False
        for r in options_downstream_only_compiled:
            if r.match(k) is not None:
                filtered = True
                break
        # Also check if we have any options that we filtered-out in first pass, yet we have them in downstream.
        for r in options_filter_out_compiled:
            if r.match(k) is not None:
                downstream_filtered_out.append(k)
                break
        if filtered:
            continue

        if not k in nixos:
            new_downstream_options.append(k)

    # Pass 3. Options are present both in NixOS and nix-devcontainer, make sure definitions match.
    for k in devcontainer:
        if k not in nixos:
            continue

        opt_devcontainer = devcontainer[k]
        opt_nixos = nixos[k]

        compare_args = {}
        # Some options have permanently changed descriptions, compared to NixOS.
        # Still we want to track upstream changes in description to catch any possibly relevant changes.
        if k == "environment.variables":
            compare_args["expected_nixos_description_md5"] = (
                "2eb29e5b435601345a2ea9dd48b1b15c"
            )
        elif k == "users.groups":
            compare_args["expected_nixos_description_md5"] = (
                "0d408411e84e5d29d33e522dd8507883"
            )
        elif k == "users.users":
            compare_args["expected_nixos_description_md5"] = (
                "9ad63e5dec92d184f6cc1c8396213e0e"
            )
        elif k == "users.users.<name>.uid":
            compare_args["expected_nixos_description_md5"] = (
                "27049922cc5261195ded25e6cc76ec95"
            )
            # NixOS allows to not specify UID, in that case UID is chosen on activation.
            # We do not support activation, we want to build image that is fully usable without
            # any runtime init hooks (as those can't be reliably used in standard containers),
            # so we require any UIDs to defined at build time.
            compare_args["ignore_default"] = True
            compare_args["expected_nixos_type"] = "null or signed integer"
        elif k == "nix.nixPath":
            # Ignore, we need custom logic for setting things up.
            compare_args["ignore_default"] = True
        elif k == "users.users.<name>.extraGroups":
            compare_args["expected_nixos_type"] = "list of string"
        elif k == "users.users.<name>.group":
            compare_args["expected_nixos_type"] = "string"
            compare_args["ignore_default"] = True
        elif k == "security.enableWrappers":
            compare_args["expected_nixos_description_md5"] = (
                "13bf7056ec7203eec2f8d4d89fbb45da"
            )
        elif k == "users.defaultUserShell":
            compare_args["ignore_default"] = True
        elif k == "nix.channel.enable":
            compare_args["expected_nixos_description_md5"] = (
                "390f930b0faae467a04155f340ea7ff3"
            )

        diff = options_compare(k, opt_devcontainer, opt_nixos, **compare_args)
        if len(diff) > 0:
            differing_options[k] = diff

    # Report
    have_bad_regexes = False
    for i, good in enumerate(regex_good_or_bad):
        if not good and not have_bad_regexes:
            print(
                "These regexes no longer match any options in upstream NixOS and may be removed:",
                file=sys.stderr,
            )
            have_bad_regexes = True
        if not good:
            print(f"  {options_filter_out[i]}", file=sys.stderr)

    error = False
    if len(new_upstream_options) > 0:
        error = True
        print(
            "NixOS has new options we need to decide what to do about:", file=sys.stderr
        )
        for opt in new_upstream_options:
            print(f"  {opt}", file=sys.stderr)

    if len(new_downstream_options) > 0:
        error = True
        print(
            "We have some downstream options, not present in current NixOS (possibly have been removed):",
            file=sys.stderr,
        )
        for opt in new_downstream_options:
            print(f"  {opt}", file=sys.stderr)

    if len(downstream_filtered_out) > 0:
        error = True
        print(
            "Some options are present in nix-devcontainer, yet we ignore equivalents from NixOS (too strong regexes?):",
            file=sys.stderr,
        )
        for opt in downstream_filtered_out:
            print(f"  {opt}", file=sys.stderr)

    if len(differing_options) > 0:
        error = True
        print(
            "Definitions of these options differ between nix-devcontainer and NixOS:",
            file=sys.stderr,
        )
        for k, v in differing_options.items():
            print(f"  {k}:", file=sys.stderr)
            for k, v in v.items():
                devcontainer = v[0]
                nixos = v[1]
                if k == "default":
                    print(f"    default changed", file=sys.stderr)
                else:
                    print(f"    {k}: {devcontainer} -> {nixos}", file=sys.stderr)

    if error:
        sys.exit(1)


if __name__ == "__main__":
    main()
