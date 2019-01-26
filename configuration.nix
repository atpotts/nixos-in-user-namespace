{pkgs, lib, ...}:
{
  imports = [./bind-mounts.nix];
  config = {
    system.build.earlyMountScript =
      "${pkgs.writeText "hello.sh" "echo hello; echo hello > /dev/null"}";
    # boot.specialFileSystems = lib.mkForce [];
    boot.isContainer = true;
    networking.hostName = "mycontainer";
    networking.useDHCP = lib.mkForce false;
    services.postgresql.enable = true;
    services.postgresql.superUser = "root";
    services.nginx.enable = true;
    services.sshd.enable = true;
    services.resolved.enable = lib.mkForce false;
    services.nscd.enable = lib.mkForce false;

    # services.nscd.enable = false;
    systemd.services.systemd-vconsole-setup.enable = false;
    services.dhcpd4.enable = lib.mkForce false;
    services.dhcpd6.enable = lib.mkForce false;
    networking.firewall.enable = false;

    environment.systemPackages = with pkgs; [
      socat
      bashInteractive
      netcat
      psmisc
      stress
      python
      postgresql
      kmod
    ];

    security.sudo.enable = true;
    # Fancy stuff to enable wrappers to work
    users.groups.nogroup.gid = lib.mkForce 999;
    rootowns.sudo="${pkgs.sudo}";
    system.activationScripts.enablesudo = ''
      # some bits of the store need to be owned by root
      mkdir -p /wraps
      cp -r ${pkgs.sudo} /wraps/sudo
      chown -R root /wraps/sudo
      mount --bind /wraps/sudo ${pkgs.sudo}
      echo "hellosudo"
      echo "hellosudo" >/dev/null
    '';
    system.activationScripts.resolvconf = lib.mkForce "";
    system.activationScripts.specialfs = lib.mkForce "";
  };

}
