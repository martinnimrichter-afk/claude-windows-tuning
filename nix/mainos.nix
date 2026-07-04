# mAIn OS — headless personality (Phase 0)
#
# This module encodes the design principles from docs/main-os/VISION.md at the
# host-substrate layer: minimal, immutable-leaning, headless. No GUI, no human
# desktop cruft. A `mainos.dev` toggle re-adds a shell + serial login for hacking.
{ config, lib, pkgs, ... }:

let
  cfg = config.mainos;
in
{
  options.mainos = {
    dev = lib.mkEnableOption "developer conveniences (interactive shell, serial getty, extra tools)";
  };

  config = {
    # ---- microVM / Firecracker guest ----
    microvm = {
      hypervisor = "firecracker";
      vcpu = 2;
      mem = 512;
      # microvm.nix defaults: read-only /nix store share + a writable /var volume.
      # A single virtio-net interface via a host TAP device.
      interfaces = [{
        type = "tap";
        id = "vm-mainos";
        mac = "02:00:00:6d:61:69"; # locally-administered; "mai"
      }];
    };

    # ---- identity ----
    networking.hostName = "mainos";
    networking.useDHCP = lib.mkDefault false;
    # Static link-local by default; real networking is a later-phase concern.
    networking.interfaces.eth0.ipv4.addresses = lib.mkDefault [{
      address = "10.0.0.2";
      prefixLength = 24;
    }];

    # ---- strip the human-facing OS ----
    # No X, no sound, no printing, no bluetooth, no desktop anything.
    services.xserver.enable = false;
    sound.enable = false;
    hardware.bluetooth.enable = false;
    services.printing.enable = false;
    # No documentation shipped into the image — smaller, immutable, headless.
    documentation.enable = lib.mkDefault false;
    documentation.man.enable = lib.mkDefault false;
    documentation.nixos.enable = false;

    # Boot straight to multi-user; nothing interactive by default.
    services.getty.autologinUser = lib.mkIf cfg.dev "root";

    # In production keep the toolbox empty; dev build gets a usable shell.
    environment.defaultPackages = lib.mkIf (!cfg.dev) (lib.mkForce [ ]);
    environment.systemPackages = lib.mkIf cfg.dev (with pkgs; [ busybox htop iproute2 ]);

    # Serial console (Firecracker exposes ttyS0); interactive login only in dev.
    boot.kernelParams = [ "console=ttyS0" ];
    services.getty.extraArgs = lib.mkIf (!cfg.dev) [ "--noclear" ];

    # ---- immutable-leaning defaults ----
    # Users are declarative; no ad-hoc useradd, no mutable passwd in prod.
    users.mutableUsers = false;
    # Dev-only root password so you can actually log in over the serial console.
    users.users.root.password = lib.mkIf cfg.dev "mainos";

    # Trim default services that make no sense on a headless agent host.
    services.udisks2.enable = false;
    programs.command-not-found.enable = false;

    system.stateVersion = "25.05";
  };
}
