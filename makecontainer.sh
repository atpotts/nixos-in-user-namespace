#!/usr/bin/env bash

login () {
  nsenter -t $(cat .pid) --all chroot $(pwd)/system  "$@"
}

build () {
  NIXOS_CONFIG=$(pwd)/configuration.nix nixos-rebuild build
}

cu=$(realpath $(which coreutils))
curun () {
  prg=$1
  shift
  echo $cu --coreutils-prog=$prg "$@"
}

cleanname="container-$(pwd | sed "s:$HOME::g; s:[^a-zA-Z1-9-]:-:g; s:^-*::")"
echo $cleanname

# poor man's networking - unix domain sockets are bind-mounted
# in both partners - making the link available to the outside world
link () {
  host=$1
  hostport=$2
  container=$3
  containerport=$4
  name=$(
    echo "link $(basename $(realpath $host)) $hostport $containerport $(basename $(realpath $container))"\
    | sed "s:[^a-zA-Z0-9-]\+:-:g; s:-\+:-:g")
  if [ $# -gt 4 ]; then
    protocol=$5
  else
    protocol=TCP4
  fi
  sh=$(realpath $(which sh))
  umount=$(realpath $(which umount))
  rmdir=$(curun rmdir)


  # we cheet by running external commands from within the container
  # because, we know they will be available in /nix/store
  dirs=$(sharedir $host $container)
  read realtmp hosttmp containertmp <<<"$dirs"

  echo starting unit $name.service
  systemd-run --user --unit="$name"\
    -p ExecStopPost="-$sh -c '[ $container != - ] && $(in_it $container $sh -c '"' "$umount $containertmp; $rmdir $containertmp" '"')'"\
    -p ExecStopPost="-$sh -c '[ $host != - ] && $(in_it $host $sh -c '"' "$umount $hosttmp; $rmdir $hosttmp" '"')'"\
    -p ExecStopPost="$(curun rmdir) $realtmp"\
    $sh -c "
      trap 'exit 0' SIGHUP
      trap 'exit 0' SIGINT
      trap 'exit 0' SIGTERM
      $(in_it $container $(realpath $(which socat))\
         UNIX-LISTEN:$containertmp/sock,fork,reuseaddr\
         $protocol:localhost:$containerport) &
      export pid=\$!
      echo pid \$pid
      $(in_it $host $(realpath $(which socat))\
         $protocol-LISTEN:$hostport,fork,reuseaddr,bind=127.0.0.1\
         UNIX-CLIENT:$hosttmp/sock)
      "
}


sharedir () {
  d="$(realpath $(mktemp -d))"
  echo $d $(mount_tmp $d $1) $(mount_tmp $d $2)
  echo "shared dir" 1>&2
}



in_it () {
  # takes either a directory or - for the host namespace
  loc=$1
  shift
  case $loc in
    -) echo "$@";;
    *) loc="$(realpath $loc)"
       echo "$(realpath $(which nsenter)) -t $($(which cat) "$loc/.pid") --all\
             $(curun chroot) \"$loc/system\"\
             $@";;
  esac
}

mount_tmp() {
    # directory must be visible in the containers mount namespace
    # but need not be visible in its chroot
    directory=$1
    container=$2
    case $container in
      -) echo $directory;;
      *)
          rootdir=$(root $container)
          newdir=$(mktemp -d -p $rootdir/tmp)
          $(enter_container $container) sh -c "mkdir $newdir; mount --bind $directory $newdir"
          echo ${newdir#$rootdir};;
    esac
}

root () {
  case $1 in
    -) echo "/";;
    *) echo $(realpath $1)/system;;
  esac
}

enter_container () {
  loc=$1
  shift; shift;
  case $loc in
    -) echo "$@";;
    *) pid=$(cat $loc/.pid)
       echo nsenter -t $pid --all "$@";;
  esac
}



start () {
  name=$(id -un)
  uid=$(id -u)
  gid=$(id -g)
  echo $name $uid $gid

  get_ranges () {
    case $2 in
      uid) echo -n "0 $uid 1 ";;
      gid) echo -n "0 $gid 1 ";;
    esac
    initial=1
    grep $1 /etc/sub$2\
    | while IFS=: read  user start range; do
      echo $initial $start $range
      let initial=initial+range
    done\
    | head -n 1\
    | tr '\n' ' '
    echo ""
  }

  export uidrange=$(get_ranges $name uid)
  export gidrange=$(get_ranges $name gid)

  # TODO: Workout how to shut this down
  # TODO: deal with race condition
  # TODO: generic readiness signalling
  export PID=$$
  echo $PID > .pid
  echo $PID $uidrange $gidrange

  (while ! eval newuidmap $PID $uidrange; do
     sleep 0.01
   done && eval newgidmap $PID $gidrange) &
  echo "eval newuidmap $PID $uidrangee"
  echo "eval newgidmap $PID $gidrangee"

  # User Mount Process Namespace
  exec unshare -Up sh - <<'EOF'
    # we need to fork to enter the process namespace
    # busy-wait until users are set up
    (sh - <<'EOFFORK'
    echo "waiting for permissions"
    set -e
    while [ "$(id -u)" != "0" ] || [ "$(id -g)" != "0" ]; do
        sleep 0.01s
    done
    echo "permissions gained"
    wait #clean up zombies
    # we need to do some black magic to get sys mounting permissions

  # Cgroup s, net, ... everythin else -- needed for sys mounting permissions
  exec unshare -Cmiun --mount-proc sh -c "exec unshare -C sh -" <<'NETEOF'
      set -e
      mkdir -p system/sys system/proc system/dev \
              system/tmp system/run

      mount -t sysfs  -o ro /sys system/sys || true

      # mount /sys/fs/cgroup if not already done
      mount -t tmpfs -o uid=0,gid=0,mode=0755 cgroup system/sys/fs/cgroup

      # (
      #   cd system/sys/fs/cgroup

      #   get/mount list of enabled cgroup controllers
      #   for sys in $(awk '!/^#/ { if ($4 == 1) print $1 }' /proc/cgroups); do
      #     mkdir $sys
      #     if ! mountpoint -q $sys; then
      #       if ! mount -n -t cgroup -o $sys cgroup $sys; then
      #         rmdir $sys || true
      #       fi
      #     fi
      #   done
      # )


      echo $(whoami)
      mount -t tmpfs tmpfs ./system/tmp
      mount -t ramfs ramfs ./system/run
      mkdir -p ./system/run/wrappers
      ls -la ./system/run/
      mount --rbind /proc ./system/proc
      # echo $$
      # ls /proc
      # exit 1

      # set up dev DOESN'T LIKE BEING A TMPFS -- breaks permissions
      # ramfs seems fine
      # needs to be a real fs
      # mount --bind /dev ./system/dev
      # mount -t devtmpfs devtmpfs ./system/dev
      mount_devs () {
        mkdir -p ./system/dev
        mount -t ramfs ramfs ./system/dev
        for a in "$@"; do
          echo mounting $a dev
          touch "./system/dev/$a"
          mount --bind "/dev/$a" "./system/dev/$a"
        done
      }
      mount_devs console urandom random null full zero tty ptmx fuse
      mkdir -p ./system/dev/pts
      mount devpts ./system/dev/pts -t devpts
      mount --bind /dev/stdout ./system/dev/console
        # mount --bind /dev/urandom ./system/dev/urandom
        # mount --bind /dev/random ./system/dev/random
        # mount --bind /dev/null ./system/dev/null
        # mount --bind /dev/full ./system/dev/full
        # mount --bind /dev/zero ./system/dev/zero
        # mount --bind /dev/tty ./system/dev/tty
        # mount --bind /dev/fuse ./system/dev/fuse
        mount --bind ./system/dev/pts/ptmx ./system/dev/ptmx
        ls -la ./system/dev
      mkdir -p system/nix/store system/result
      mount --bind /nix/store system/nix/store
      mount --bind result system/result

      wait
      export container=nixos

    # mkdir -p system/run/resolvconf/interfaces
    # touch systemd run/resolvconf/interfaces/systemd
    # exec systemd
    # t=$(mktemp -p system)
    # < result/init sed 
    exec chroot system result/init

NETEOF
EOFFORK
) &
echo $! > .pid
wait
EOF
}


cmd=$1
shift
case $cmd in
  start) start;;
  stop) login shutdown 0
    rm .pid
  ;;
  login) login "$@";;
  build) build "$@";;
  switch) build "$@" && login result/activate ;;
  link) link "$@";;
esac

