{pkgs, lib, ...}:
{
  boot.isContainer = true;
  networking.hostName = "mycontainer";
  services.postgresql.enable = true;
  services.postgresql.superUser = "root";
  services.nginx.enable = true;
  services.sshd.enable = true;

  # services.nscd.enable = false;
  systemd.services.systemd-vconsole-setup.enable = false;
  services.dhcpd4.enable = lib.mkForce false;
  services.dhcpd6.enable = lib.mkForce false;

  environment.systemPackages = [pkgs.socat pkgs.bashInteractive pkgs.netcat];

  security.sudo.enable = true;
  # Fancy stuff to enable wrappers to work
  users.groups.nogroup.gid = lib.mkForce 999;
  #system.activationScripts.specialfs = lib.mkForce "";
  system.activationScripts.enablesudo = ''
    # some bits of the store need to be owned by root
    mkdir -p /wraps
    cp -r ${pkgs.sudo} /wraps/sudo
    mount --bind /wraps/sudo ${pkgs.sudo}
  '';

}
