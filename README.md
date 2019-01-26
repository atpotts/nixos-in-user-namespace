# NixOS user containers

For a overview of this exercise, please see [my blog post][https://atpotts.uk/blog/posts/2019-01-26-namespaces-1.html].

## NB: This is a buggy and insecure experiment - use at your own risk

This is an experiment with being able to run nixos-modules in user-space - intended
to support development environments. Having been unable to persuade systemd
to run a third instance in addition to the system and user instances, I ended
up exploring 

I have (as you will see by reading any code here) a bad habit of experimenting
in dodgy and dangerous ways. For which reason, I would rather avoid going anywhere
near root just to e.g. set up services. With a properly configured system,
this should let you run some nixos configurations from within your userspace.

Be careful with the port forwarding thingy - make sure you have a proper firewall, as I have no
idea whether it will try to open up ports to the outside world.

The aim is to be able to run services in development environments **based on
nixos configurations** without ever having to go near root.

You should never need to type sudo once it is set up, however.

You need:

  1. subuid ranges set up for your user (in /etc/subuid and /etc/subgid). Nixos
     will probably want a few thousand. Nixos extraUsers has a subUidRanges and
     subGidRanges options

  2. NixOs 18.09 (fixed an issue with the kernel keyring - systemd now blocks)

  3. setuid wrapped versions of newuidmap and newgid map on the path (
      nixos installs these by default, I think)

  4. socat should be installed on the host (and implicitly the containers, due
     to nix-store sharing) to enable setting up port forwarding

  5. A running systemd user instance.

clone this directory, and change the configuration.nix at will. (NB. the wierd
things at the bottom are necessary with the nogroup gid and chowning sudo are necessary
to enable a successful boot - **TODO** create a clean wrapper that will do
this automatically for a nixos module & explore using overlayfs or something
to manage the chowning more tidily and with less copying.)

# Running

With the exception of 'link', ./makecontainer.sh should currently always be run
from the directory containing `configuration.nix`


 -  `./makecontainer.sh build` will run nixos-rebuild to create
 -  `./makecontainer.sh start` will launch the container, printing systemd
    output to the standard output of the launching terminal
 -  `./makecontainer.sh switch` will rebuild and attempt to run the activation
    script - it doesn't seem to work reliably, I suspect because fancier things
    need to be done to get systemd to pick it up
 -  `./makecontainer.sh login` will nsenter and chroot the current shell into
    the container (it doesn't start a session - which I think is probably entirely
    unneccessary for this sort of lightweight thingamajig)
 -  `./makecontainer.sh link (client-directory) (client-port) (host-directory) (host-port)`
    will establish a poor man's network link between tow containers or between the 
    containers and the host. This is needed as it seems that root permissions are
    needed to set up veth links, so that isn't great for unprivileged sandbox work.

    the special symbol `-` is used instead of host or client directory when referring
    to the host machine.

    to connect to postgres on a container with `configuration.nix` in ~/cont1
    I would type `./makecontainer.sh link - 1001 ~/cont1 5432`, and then I could
    log-in from the host with `psql -h localhost -p 1001`.

    To enable me to access a web server in container two from container 1:
    `./makecontainer.sh link ~/cont1 80 ~/cont2 80`, then I can `curl localhost:80`.

    These work by using socat over unix domain sockets - currently only lightly
    tested with TCP on IPV4. They set up a sensibly named systemd service to
    manage the link, which can then be managed with `systemctl --user`
  

# Todo

- get rid of the nasty ~/.pid file
- find a neater workaround for sudo - investigate what other services require
  their library files to be owned by root
- tidy up the code - make it at least sligthly less horrificly lacking in robustness
- allow systemd to launch the containers themselves, as well as managing the 
  port links
- construct a more minimal base configuration (we don't really need login,
     ... - we are just running some services)
- think about outbound networking
- test more things
- CGROUPS do not currently work - so there is no resource management. Investigate!

