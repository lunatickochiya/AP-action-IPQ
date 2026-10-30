#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 RK-action
#
# 复用 runner 自带的 Go / LLVM，避免 OpenWrt 从源码编 host Go 和 LLVM：
#   - Go:   CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT -> runner GOROOT
#   - LLVM: CONFIG_BPF_TOOLCHAIN_HOST_PATH -> runner LLVM prefix（仅 eBPF 构建）
#   - Python: 关闭 host Python 的 PGO（--enable-optimizations -> --disable-optimizations）
#
# 必须在 feeds 安装完成、.config 已生成之后运行。

set -euo pipefail

info() { echo "[prepare-build-host] $*"; }
warn() { echo "::warning ::[prepare-build-host] $*"; }

# ---------- Go external bootstrap ----------
GO_BIN=$(command -v go 2>/dev/null || true)
if [ -z "$GO_BIN" ]; then
	GO_BIN=$(ls -1d /opt/hostedtoolcache/go/*/x64/bin/go 2>/dev/null | sort -V | tail -n1 || true)
fi
if [ -n "$GO_BIN" ] && [ -x "$GO_BIN" ]; then
	GO_ROOT=$("$GO_BIN" env GOROOT)
	GO_VER=$("$GO_BIN" version | awk '{print $3}' | sed 's/^go//')
	GO_MAJOR=${GO_VER%%.*}
	GO_REST=${GO_VER#*.}
	GO_MINOR=${GO_REST%%.*}
	# 至少要满足 feed 里 golang-bootstrap 的版本，否则引导目标 Go 会失败。
	BOOTSTRAP_GO=$(sed -n 's/^GO_VERSION_MAJOR_MINOR:=//p' \
		feeds/packages/lang/golang/golang-bootstrap/Makefile 2>/dev/null | head -n1) || true
	BOOTSTRAP_GO=${BOOTSTRAP_GO:-1.24}
	BOOT_MAJOR=${BOOTSTRAP_GO%%.*}
	BOOT_MINOR=${BOOTSTRAP_GO#*.}
	if [ -n "$GO_ROOT" ] && [ -x "$GO_ROOT/bin/go" ] \
		&& { [ "$GO_MAJOR" -gt "$BOOT_MAJOR" ] 2>/dev/null \
			|| { [ "$GO_MAJOR" -eq "$BOOT_MAJOR" ] && [ "$GO_MINOR" -ge "$BOOT_MINOR" ]; } 2>/dev/null; }; then
		sed -i '/^CONFIG_GOLANG_BUILD_BOOTSTRAP=/d; /^# CONFIG_GOLANG_BUILD_BOOTSTRAP is not set$/d; /^CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT=/d' .config
		{
			echo '# CONFIG_GOLANG_BUILD_BOOTSTRAP is not set'
			printf 'CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT="%s"\n' "$GO_ROOT"
		} >> .config
		info "Go bootstrap root: $GO_ROOT (go$GO_VER, feed bootstrap >= $BOOTSTRAP_GO)"
	else
		warn "runner Go $GO_VER is older than feed bootstrap $BOOTSTRAP_GO (or GOROOT invalid), skip external bootstrap"
	fi
else
	warn "runner has no go, host Go will be built from source"
fi

# ---------- eBPF: host LLVM ----------
if grep -qx 'CONFIG_BPF_TOOLCHAIN_HOST=y' .config; then
	LLVM_ROOT=$(llvm-config --prefix 2>/dev/null || true)
	if [ -z "$LLVM_ROOT" ] && command -v clang >/dev/null 2>&1; then
		LLVM_ROOT=$(dirname "$(dirname "$(readlink -f "$(command -v clang)")")")
	fi
	if [ -n "$LLVM_ROOT" ] && [ -x "$LLVM_ROOT/bin/clang" ]; then
		SMOKE=$(mktemp -d)
		printf 'int wrt_bpf_smoke(void) { return 0; }\n' > "$SMOKE/smoke.c"
		if "$LLVM_ROOT/bin/clang" --target=bpfel -O2 -c "$SMOKE/smoke.c" -o "$SMOKE/smoke.o" >/dev/null 2>&1; then
			sed -i '/^CONFIG_BPF_TOOLCHAIN_HOST_PATH=/d' .config
			printf 'CONFIG_BPF_TOOLCHAIN_HOST_PATH="%s"\n' "$LLVM_ROOT" >> .config
			info "BPF LLVM prefix: $LLVM_ROOT"
		else
			warn "clang at $LLVM_ROOT cannot target bpfel, keep default PATH lookup"
		fi
		rm -rf "$SMOKE"
	else
		warn "llvm-config/clang not found, keep default PATH lookup"
	fi
fi

# ---------- host Python: disable PGO ----------
PYTHON_MAKEFILE=feeds/packages/lang/python/python3/Makefile
if [ -f "$PYTHON_MAKEFILE" ]; then
	# 只改 HOST_CONFIGURE_ARGS 段，target Python 的 --enable-optimizations 保持不动。
	sed -i '/^HOST_CONFIGURE_ARGS[[:space:]]*+=/,/^$/s/--enable-optimizations/--disable-optimizations/' "$PYTHON_MAKEFILE"
	if sed -n '/^HOST_CONFIGURE_ARGS/,/^$/p' "$PYTHON_MAKEFILE" | grep -q -- '--disable-optimizations'; then
		info "host Python PGO disabled"
	else
		warn "host Python PGO not found (feed layout changed?), keep as-is"
	fi
fi
