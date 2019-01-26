{pkgs, lib, ...}:
{
  config = {
    # some test services
    services.postgresql.enable = true;
    services.postgresql.superUser = "root";
    services.nginx.enable = true;
    services.sshd.enable = true;


    boot.isContainer = true;
    networking.hostName = "mycontainer";


    environment.systemPackages = with pkgs; [
      socat
      bashInteractive
      psmisc
    ];

    # Fancy stuff to enable wrappers to work
    # We need a working nogroup (which isn't just a dump for host users)
    users.groups.nogroup.gid = lib.mkForce 999;

    security.sudo.enable = true;
    # some bits of the store need te be owned by root
    system.activationScripts.enablesudo = ''
      mkdir -p /wraps
      cp -r ${pkgs.sudo} /wraps/sudo
      chown -R root /wraps/sudo
      mount --bind /wraps/sudo ${pkgs.sudo}
    '';

    # some things don't just make sense in this context
    system.build.earlyMountScript =
      "${pkgs.writeText "no-op.sh" "echo nothing > /dev/null"}";
    system.activationScripts.resolvconf = lib.mkForce "";
    system.activationScripts.specialfs = lib.mkForce "";

    # disable a load of networking stuff (too many lines - not sure
    # which ones we need)
    networking.useDHCP = lib.mkForce false;
    services.resolved.enable = lib.mkForce false;
    services.nscd.enable = lib.mkForce false;
    systemd.services.systemd-vconsole-setup.enable = false;
    services.dhcpd4.enable = lib.mkForce false;
    services.dhcpd6.enable = lib.mkForce false;
    networking.firewall.enable = false;
  };

}
