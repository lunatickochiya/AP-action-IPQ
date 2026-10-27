#!/bin/bash
# 本地化/精简版构建环境初始化（RK-action / AP-action / AP-action-IPQ / Pon-Action 共用）
#
# 与 ImmortalWrt 上游 init_build_environment.sh 的差异：
#   - 不做 apt full-upgrade：上游会升级 99 个包（内核/systemd/php/...），
#     下载 400MB+，镜像慢时初始化能卡 1~2 小时；
#   - 不添加 nodesource / yarn / llvm-toolchain / git-core / golang / github-cli
#     等第三方 apt 源，也不再从 keyserver.ubuntu.com 拉 GPG key：
#     这些源或 keyserver 慢/不可达时，初始化会直接挂住；
#   - 不再安装/编译 upx、padjffs2、po2lmo（OpenWrt 构建时会自己编这些 host 工具）；
#   - 所有 apt 操作带超时和重试。
#
# 依赖列表取自上游脚本，保证 OpenWrt 构建所需的主机工具齐全。
set -eo pipefail

export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

APT_OPTS=(-y -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30)

echo "[INFO] apt-get update"
apt-get update "${APT_OPTS[@]}" || apt-get update "${APT_OPTS[@]}"

echo "[INFO] installing build dependencies (Ubuntu 仓库)"
apt-get install "${APT_OPTS[@]}" \
	ack antlr3 asciidoc autoconf automake autopoint binutils bison \
	build-essential bzip2 ccache clang cmake cpio curl device-tree-compiler ecj fakeroot \
	fastjar flex gawk gettext genisoimage gnutls-dev gperf haveged help2man intltool \
	irqbalance jq lld llvm lib32gcc-s1 libc6-dev-i386 libelf-dev libglib2.0-dev \
	libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses-dev libreadline-dev \
	libssl-dev libtool libyaml-dev libz-dev lrzsz msmtp nano ninja-build p7zip \
	p7zip-full patch pkgconf libpython3-dev python3 python3-pip python3-cryptography \
	python3-docutils python3-ply python3-pyelftools python3-requests qemu-utils quilt \
	re2c rsync scons sharutils squashfs-tools subversion swig texinfo uglifyjs unzip \
	vim wget xmlto zlib1g-dev zstd xxd

# 与上游一致：部分 host 工具会 include <asm/...>
[ -e /usr/include/asm ] || ln -svf "/usr/include/$(gcc -dumpmachine)/asm" /usr/include/asm

apt-get clean

echo "[SUCCESS] build dependencies installed"
