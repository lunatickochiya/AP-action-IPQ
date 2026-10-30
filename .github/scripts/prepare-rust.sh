#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 RK-action
#
# 用 runner 自带的 rustup 替代 OpenWrt 的 rust/host 源码构建。
#
# 背景：feeds/packages/lang/rust 默认要从源码编 rustc，4 vCPU 上约 4 小时。
# 这里按 feed 的 PKG_VERSION 安装同版本 rustup toolchain，补上目标 std，
# 再把 Host/Prepare、Host/Configure、Host/Compile 置空、Host/Install 改成
# 软链，OpenWrt 就会认为 rust/host 已装好，直接使用 runner 的 rustc/cargo。
#
# 必须在 feeds 安装完成、.config 已生成之后运行。

set -euo pipefail

RUST_FEED="$PWD/feeds/packages/lang/rust"
RUST_MAKEFILE="$RUST_FEED/Makefile"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if [ ! -f "$RUST_MAKEFILE" ]; then
	echo "rust feed not installed, skip"
	exit 0
fi

# 没有选中 rust 相关包时不必下载/安装 toolchain（SDK 只编几个 LuCI 包时很常见）。
# 列表覆盖 OpenWrt 里常见的 rust/host 消费者；漏掉的包会回退到源码构建，不会出错。
if [ -f .config ] && ! grep -qE '^CONFIG_PACKAGE_(rust|ruby|luci-app-quickfile|shadowsocks-rust|python3-cryptography|fish|ripgrep|eza|lsd|procs|dufs|bottom|netavark|aardvark-dns)=' .config; then
	echo "no rust consumers in .config, skip rust injection"
	exit 0
fi

FEED_VERSION=$(sed -n 's/^PKG_VERSION:=//p' "$RUST_MAKEFILE" | head -n1 | tr -d '[:space:]')
FEED_VERSION=${FEED_VERSION%%-*}
if [ -z "$FEED_VERSION" ]; then
	echo "::warning ::cannot read PKG_VERSION from $RUST_MAKEFILE, skip rust injection"
	exit 0
fi

# Ask the feed for the Rust target triple, so CI and OpenWrt use the same mapping.
RUST_TARGET=$(make --no-print-directory -s -f - TOPDIR="$PWD" ci-rust-target <<'MAKE'
include $(TOPDIR)/rules.mk
include $(TOPDIR)/feeds/packages/lang/rust/rust-values.mk
.PHONY: ci-rust-target
ci-rust-target:
	@printf '%s\n' '$(RUSTC_TARGET_ARCH)'
MAKE
)
if [ -z "$RUST_TARGET" ]; then
	echo "::warning ::cannot determine Rust target triple, skip rust injection"
	exit 0
fi

if ! command -v rustup >/dev/null 2>&1; then
	if [ -x "$HOME/.cargo/bin/rustup" ]; then
		PATH="$HOME/.cargo/bin:$PATH"
		export PATH
	else
		echo "::warning ::rustup not found on runner, skip rust injection (rust will be built from source)"
		exit 0
	fi
fi

HOST_TRIPLE=$(rustc -vV 2>/dev/null | sed -n 's/^host: //p' || true)
if [ -z "$HOST_TRIPLE" ]; then
	HOST_TRIPLE=$(rustup show 2>/dev/null | sed -n 's/^Default host: //p' | head -n1 || true)
fi
if [ -z "$HOST_TRIPLE" ]; then
	echo "::warning ::cannot determine Rust host triple, skip rust injection"
	exit 0
fi

TOOLCHAIN="$FEED_VERSION-$HOST_TRIPLE"
if ! rustup toolchain list | awk '{print $1}' | grep -qx "$TOOLCHAIN"; then
	echo "installing Rust $TOOLCHAIN (feed PKG_VERSION=$FEED_VERSION)"
	if ! rustup toolchain install "$FEED_VERSION" --profile minimal --no-self-update; then
		echo "::warning ::rustup cannot install $FEED_VERSION, fallback to active toolchain"
		TOOLCHAIN=$(rustup show active-toolchain | awk '{print $1}')
	fi
fi

echo "Rust toolchain: $TOOLCHAIN"
echo "Rust target:    $RUST_TARGET"
rustup target add --toolchain "$TOOLCHAIN" "$RUST_TARGET"

RUST_ROOT=$(rustup run "$TOOLCHAIN" rustc --print sysroot)
test -d "$RUST_ROOT/lib/rustlib/$RUST_TARGET/lib"
for tool in cargo rustc rustdoc; do
	test -x "$RUST_ROOT/bin/$tool"
done

# Replace the source bootstrap before OpenWrt expands its host build rules.
{
	printf 'CI_RUST_ROOT:=%s\n' "$RUST_ROOT"
	cat "$SCRIPT_DIR/rust-prebuilt.mk"
} > "$RUST_FEED/ci-prebuilt.mk"

if ! grep -Fxq 'include ./ci-prebuilt.mk' "$RUST_MAKEFILE"; then
	sed -i '/^$(eval $(call HostBuild))$/i include ./ci-prebuilt.mk' "$RUST_MAKEFILE"
fi
grep -Fxq 'include ./ci-prebuilt.mk' "$RUST_MAKEFILE"

"$RUST_ROOT/bin/rustc" --version
echo "rust/host will use runner rust $TOOLCHAIN for $RUST_TARGET"
