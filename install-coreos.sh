#!/bin/bash
set -e
wget --no-check-certificate https://github.com/coreos/container-linux-config-transpiler/releases/download/v0.5.0/ct-v0.5.0-x86_64-unknown-linux-gnu -O ct
chmod u+x ct
if [ -e container-linux-config.json ]; then rm container-linux-config.json; fi
./ct --in-file container-linux-config.yaml | sed "s/\$SSH_KEY/$(cat ~/.ssh/authorized_keys | grep '^ssh-rsa' | sed -n 1p | sed 's/\//\\\//g')/g" > container-linux-config.json
apt-get update && apt-get -y install gawk bzip2
wget --quiet https://raw.githubusercontent.com/coreos/init/master/bin/coreos-install -O coreos-install
chmod u+x coreos-install
./coreos-install -d /dev/vda -i container-linux-config.json

# apt-get update
# apt-get -y install gawk bzip2 cpio
# DEBIAN_FRONTEND=noninteractive
# apt-get install debconf-utils -y
# echo "kexec-tools kexec-tools/load_kexec boolean false" | debconf-set-selections
# apt-get install squashfs-tools kexec-tools -y
# wget --quiet https://raw.githubusercontent.com/coreos/init/master/bin/coreos-install
# chmod u+x coreos-install
# ./coreos-install -d /dev/vda -i /root/container-linux-config.json

#
# wget http://stable.release.core-os.net/amd64-usr/current/coreos_production_pxe.vmlinuz -O kernel
# wget http://stable.release.core-os.net/amd64-usr/current/coreos_production_pxe_image.cpio.gz -O initrd.cpio.gz
# gunzip initrd.cpio.gz
# find usr | cpio -o -A -H newc -O initrd.cpio
# gzip initrd.cpio
# kexec -l kernel --initrd initrd.cpio.gz --append='coreos.autologin=tty1'
# echo "Rebooting"
# bash -c "sleep 2; kexec -e" >/dev/null 2>&1 &
#
# DEVICE="/dev/vda"
# ROOT_DEV=$(blkid -t "LABEL=ROOT" -o device "${DEVICE}"*)
# WORKDIR=$(mktemp --tmpdir -d coreos-install.XXXXXXXXXX)
# mkdir -p "${WORKDIR}/rootfs"
# case $(blkid -t "LABEL=ROOT" -o value -s TYPE "${ROOT_DEV}") in
#   "btrfs") mount -t btrfs -o subvol=root "${ROOT_DEV}" "${WORKDIR}/rootfs" ;;
#   *)       mount "${ROOT_DEV}" "${WORKDIR}/rootfs" ;;
# esac
# trap 'umount "${WORKDIR}/rootfs"' RETURN
#
# mkdir -p "${WORKDIR}/rootfs/opt"
# wget http://stable.release.core-os.net/amd64-usr/current/coreos_production_pxe.vmlinuz -O ${WORKDIR}/rootfs/opt/kernel
# wget http://stable.release.core-os.net/amd64-usr/current/coreos_production_pxe_image.cpio.gz -O ${WORKDIR}/rootfs/opt/initrd.cpio.gz
# kexec --load ${WORKDIR}/rootfs/opt/kernel --initrd ${WORKDIR}/rootfs/opt/initrd.cpio.gz --append='coreos.autologin=tty1'

# WORKDIR=$(mktemp --tmpdir -d coreos-install.XXXXXXXXXX)
# OEM_DEV=$(blkid -t "LABEL=OEM" -o device "/dev/vda"*)
# mkdir -p "${WORKDIR}/oemfs"
# mount "${OEM_DEV}" "${WORKDIR}/oemfs"

# dpkg-divert --add --rename --divert /sbin/init.distrib /sbin/init
# cat > /sbin/init <<-EOF
# #!/bin/bash
#
# if grep -qv " kexeced\$" /proc/cmdline; then
#     /sbin/kexec --load /vmlinuz \
#         --reuse-cmdline \
#         --initrd=/initrd.img \
#         --append="init=/sbin/init.distrib kexeced" \
#     && /bin/mount -o ro,remount / \
#     && /sbin/kexec --exec
# fi
#
# exec /sbin/init.distrib "\$@"
# EOF
# chmod 755 /sbin/init
#
# reboot
