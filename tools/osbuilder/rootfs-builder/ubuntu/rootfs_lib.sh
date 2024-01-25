# Copyright (c) 2018 Yash Jain, 2022 IBM Corp.
#
# SPDX-License-Identifier: Apache-2.0

build_dbus() {
	local rootfs_dir=$1
	ln -sf /lib/systemd/system/dbus.service $rootfs_dir/etc/systemd/system/dbus.service
	ln -sf /lib/systemd/system/dbus.socket $rootfs_dir/etc/systemd/system/dbus.socket
}

build_rootfs() {
	local rootfs_dir=$1
	local multistrap_conf=multistrap.conf

    [ -z "$rootfs_dir" ] && die "need rootfs"
    [ "$rootfs_dir" = "/" ] && die "rootfs cannot be slash"

	# For simplicity's sake, use multistrap for foreign and native bootstraps.
	cat > "$multistrap_conf" << EOF
[General]
cleanup=true
aptsources=Ubuntu
bootstrap=Ubuntu

[Ubuntu]
source=$REPO_URL
keyring=ubuntu-keyring
suite=focal
packages=$PACKAGES $EXTRA_PKGS
EOF
	if ! multistrap -a "$DEB_ARCH" -d "$rootfs_dir" -f "$multistrap_conf"; then
		build_dbus $rootfs_dir
	fi
	rm -rf "$rootfs_dir/var/run"
	ln -s /run "$rootfs_dir/var/run"
	cp --remove-destination /etc/resolv.conf "$rootfs_dir/etc"

    if [[ "${TEE_PLATFORM}" == "tdx" || "${TEE_PLATFORM}" == "all" ]] && [ "${ARCH}" == "x86_64" ]; then
        source /etc/os-release
        if [ "${VERSION_ID}" == "20.04" ]; then
            curl -L https://download.01.org/intel-sgx/sgx_repo/ubuntu/intel-sgx-deb.key |  chroot "${rootfs_dir}" apt-key add -

            echo 'deb [arch=amd64] http://security.ubuntu.com/ubuntu focal-security main universe' | tee ${rootfs_dir}/etc/apt/sources.list.d/universe.list
            echo 'deb [arch=amd64] https://download.01.org/intel-sgx/sgx_repo/ubuntu focal main' | tee ${rootfs_dir}/etc/apt/sources.list.d/intel-sgx.list
            chroot "${rootfs_dir}" apt-get update && chroot "${rootfs_dir}" apt-get install -y libtdx-attest=1.18\* libtdx-attest-dev=1.18\*
            echo 'port=4050' | chroot "${rootfs_dir}" tee /etc/tdx-attest.conf
        else
            echo "libtdx-attest is only provided for Ubuntu 20.04, there's yet no packages for Ubuntu ${VERSION_ID}"
            exit 1
        fi
    fi

	# Reduce image size and memory footprint by removing unnecessary files and directories.
	rm -rf $rootfs_dir/usr/share/{bash-completion,bug,doc,info,lintian,locale,man,menu,misc,pixmaps,terminfo,zsh}

	# Minimal set of device nodes needed when AGENT_INIT=yes so that the
	# kernel can properly setup stdout/stdin/stderr for us
	pushd $rootfs_dir/dev
	MAKEDEV -v console tty ttyS null zero fd
	popd
}
