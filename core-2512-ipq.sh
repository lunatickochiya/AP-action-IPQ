#!/bin/bash
#=================================================

OpenWrt_PATCH_FILE_DIR="${OpenWrt_PATCH_FILE_DIR:-openwrt-2512-ipq}"
# This script is from https://github.com/lunatickochiya/Lunatic-s805-rockchip-Action
# Written By lunatickochiya
# QQ group :286754582  https://jq.qq.com/?_wv=1027&k=5QgVYsC
#=================================================

function device_config_error() {
	echo "::error title=Device config error::$*" >&2
	return 1
}
function kernel66_enabled() {
	[ "${KERNEL66:-0}" = "1" ]
}
function set_testing_kernel_config() {
	local config_file
	for config_file in machine-configs/$OpenWrt_PATCH_FILE_DIR/*.config; do
		[ -f "$config_file" ] || continue
		if ! grep -qx 'CONFIG_TESTING_KERNEL=y' "$config_file"; then
			sed -i '1iCONFIG_TESTING_KERNEL=y' "$config_file"
		fi
		if ! grep -qx 'CONFIG_HAS_TESTING_KERNEL=y' "$config_file"; then
			sed -i '1iCONFIG_HAS_TESTING_KERNEL=y' "$config_file"
		fi
	done
}
function resolve_build_matrix() {
	local workspace="${GITHUB_WORKSPACE:-$PWD}"
	local machine="${Target_CFG_Machine:-}"
	local config_dir="$workspace/machine-configs/${OpenWrt_PATCH_FILE_DIR:-}"
	local package_dir="$workspace/package-configs/${OpenWrt_PATCH_FILE_DIR:-}"
	local config_file file_name target candidate_target matrix firewall
	local target_length best_length=999999
	local ambiguous_target=false
	local -a iptables_configs

	if [[ ! "$machine" =~ ^[A-Za-z0-9._-]+$ ]]; then
		device_config_error "Invalid or empty machine name: '$machine'"
		return 1
	fi
	if [ -z "${OpenWrt_PATCH_FILE_DIR:-}" ] || [ ! -d "$config_dir" ]; then
		device_config_error "Machine config directory not found: $config_dir"
		return 1
	fi

	shopt -s nullglob
	iptables_configs=("$config_dir/${machine}-"*"-iptables.config")
	shopt -u nullglob
	if [ "${#iptables_configs[@]}" -eq 0 ]; then
		device_config_error "No ${machine}-<target>-iptables.config found in $config_dir"
		return 1
	fi

	# A machine name can prefix another machine (for example, -v2 and -v2-lite).
	# The exact machine leaves the shortest <target> suffix in the config filename.
	for config_file in "${iptables_configs[@]}"; do
		file_name="${config_file##*/}"
		candidate_target="${file_name#"${machine}-"}"
		candidate_target="${candidate_target%-iptables.config}"
		if [[ ! "$candidate_target" =~ ^[A-Za-z0-9._-]+$ ]]; then
			continue
		fi
		target_length="${#candidate_target}"
		if [ "$target_length" -lt "$best_length" ]; then
			target="$candidate_target"
			best_length="$target_length"
			ambiguous_target=false
		elif [ "$target_length" -eq "$best_length" ] && [ "$candidate_target" != "$target" ]; then
			ambiguous_target=true
		fi
	done
	if [ -z "${target:-}" ] || [ "$ambiguous_target" = true ]; then
		device_config_error "Could not uniquely resolve target for $machine in $config_dir"
		return 1
	fi

	for firewall in iptables nftables; do
		config_file="$config_dir/${machine}-${target}-${firewall}.config"
		if [ ! -s "$config_file" ]; then
			device_config_error "Missing machine config: $config_file"
			return 1
		fi
		config_file="$package_dir/${machine}-${target}-${firewall}.config"
		if [ ! -s "$config_file" ]; then
			device_config_error "Missing package config: $config_file"
			return 1
		fi
	done

	printf -v matrix '{"include":[{"target":"%s-iptables"},{"target":"%s-nftables"}]}' "$target" "$target"
	echo "Resolved $machine to target $target"
	echo "Generated matrix: $matrix"
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		echo "matrix=$matrix" >> "$GITHUB_OUTPUT"
		echo "machine=$machine" >> "$GITHUB_OUTPUT"
	else
		echo "$matrix"
	fi
}
function init_pkg_env() {
	sudo bash -c 'bash <(curl -sL https://build-scripts.immortalwrt.org/init_build_environment.sh)'
	sudo -E apt-get -qq install libgnutls28-dev coccinelle libfuse-dev \
	b43-fwcutter cups-ppdc

	sudo npm install -g pnpm
	clang --version

	sudo timedatectl set-timezone "$TZ"
	sudo mkdir -p /workdir
	sudo chown "$USER":"$GROUPS" /workdir
}
function init_gh_env_2512() {
	source "${GITHUB_WORKSPACE}/env/common.txt"
	local repo_env_file="${OpenWrt_REPO_ENV_FILE:-$OpenWrt_PATCH_FILE_DIR}"
	source "${GITHUB_WORKSPACE}/env/$repo_env_file.repo"
	local kernel66
	kernel66=$(echo "$PATCH_JSON_INPUT" | jq -r '.KERNEL66 // "0"')
	local branch firmware
	branch=$(echo "$PATCH_JSON_INPUT" | jq -r '.Branch // empty')
	if [ "$repo_env_file" = "openwrt-2512-ipq" ] && [ -n "$branch" ]; then
		REPO_BRANCH="$branch"
	fi
	if [ "$kernel66" = "1" ]; then
		REPO_URL="${KERNEL66_REPO_URL:-$REPO_URL}"
		REPO_BRANCH="${KERNEL66_REPO_BRANCH:-$REPO_BRANCH}"
	fi
	firmware=$(echo "$PATCH_JSON_INPUT" | jq -r '.IPQ_Firmware // empty')
	echo -e "KERNEL66=$kernel66" >> "$GITHUB_ENV"
	echo -e "Branch=${branch:-$REPO_BRANCH}" >> "$GITHUB_ENV"
	echo -e "IPQ_Firmware=${firmware:-ipq-nss-12-5}" >> "$GITHUB_ENV"
	echo -e "ADD_SKB_RECYCLER=$(echo "$PATCH_JSON_INPUT" | jq -r '.ADD_SKB_RECYCLER // "0"')" >> "$GITHUB_ENV"
	echo -e "ADD_eBPF=$(echo $PATCH_JSON_INPUT | jq -r ".ADD_eBPF")" >> "$GITHUB_ENV"
}
function config_json_input_set() {
	echo -e "Cache=$(echo $CONFIG_JSON_INPUT | jq -r ".Cache")" >> "$GITHUB_ENV"
	echo -e "CacheLinux=$(echo $CONFIG_JSON_INPUT | jq -r ".CacheLinux")" >> "$GITHUB_ENV"
	echo -e "CachePKGS=$(echo $CONFIG_JSON_INPUT | jq -r ".CachePKGS")" >> "$GITHUB_ENV"
	echo -e "CacheSave=$(echo $CONFIG_JSON_INPUT | jq -r ".CacheSave")" >> "$GITHUB_ENV"
	echo -e "UPLOAD_RELEASE=$(echo $CONFIG_JSON_INPUT | jq -r ".UPLOAD_RELEASE")" >> "$GITHUB_ENV"
	echo -e "ALLKMOD=$(echo $CONFIG_JSON_INPUT | jq -r ".ALLKMOD")" >> "$GITHUB_ENV"
}
function patch_json_input_set() {
	echo -e "OPENSSL_3_5=$(echo $PATCH_JSON_INPUT | jq -r ".OPENSSL_3_5")" >> "$GITHUB_ENV"
	echo -e "BCM_FULLCONE=$(echo $PATCH_JSON_INPUT | jq -r ".BCM_FULLCONE")" >> "$GITHUB_ENV"
	echo -e "TRY_BBR_V3=$(echo $PATCH_JSON_INPUT | jq -r ".TRY_BBR_V3")" >> "$GITHUB_ENV"
	echo -e "KERNEL66=$(echo $PATCH_JSON_INPUT | jq -r ".KERNEL66 // \"0\"")" >> "$GITHUB_ENV"
	echo -e "Firewall_Allow_WAN=$(echo $PATCH_JSON_INPUT | jq -r ".Firewall_Allow_WAN")" >> "$GITHUB_ENV"
	echo -e "DOCKER_BUILDIN=$(echo $PATCH_JSON_INPUT | jq -r ".DOCKER_BUILDIN")" >> "$GITHUB_ENV"
	echo -e "ADD_IB=$(echo $PATCH_JSON_INPUT | jq -r ".ADD_IB")" >> "$GITHUB_ENV"
	echo -e "ADD_SDK=$(echo $PATCH_JSON_INPUT | jq -r ".ADD_SDK")" >> "$GITHUB_ENV"
	echo -e "MAC80211_616=$(echo $PATCH_JSON_INPUT | jq -r ".MAC80211_616")" >> "$GITHUB_ENV"
}
function init_gh_env_common() {
	local diy_script
	echo "date=$(date +'%m/%d_%Y_%H/%M')" >> "$GITHUB_ENV"
	echo "date2=$(date +'%Y/%m %d')" >> "$GITHUB_ENV"
	echo "date3=$(date +'%m.%d')" >> "$GITHUB_ENV"

	echo "REPO_URL=${REPO_URL}" >> "$GITHUB_ENV"
	echo "BURN_UBOOT_IMG_URL=${BURN_UBOOT_IMG_URL}" >> "$GITHUB_ENV"
	echo "AMLIMG_TOOL_URL=${AMLIMG_TOOL_URL}" >> "$GITHUB_ENV"
	echo "REPO_BRANCH=${REPO_BRANCH}" >> "$GITHUB_ENV"
	echo "DIY_SH=${DIY_SH}" >> "$GITHUB_ENV"
	echo "DIY_SH_AFB=${DIY_SH_AFB}" >> "$GITHUB_ENV"
	echo "DIY_SH_RFC=${DIY_SH_RFC}" >> "$GITHUB_ENV"
	echo "UPLOAD_BIN_DIR=${UPLOAD_BIN_DIR}" >> "$GITHUB_ENV"
	echo "UPLOAD_IPK_DIR=${UPLOAD_IPK_DIR}" >> "$GITHUB_ENV"
	echo "UPLOAD_FIRMWARE=${UPLOAD_FIRMWARE}" >> "$GITHUB_ENV"
	echo "UPLOAD_COWTRANSFER=${UPLOAD_COWTRANSFER}" >> "$GITHUB_ENV"
	echo "UPLOAD_WETRANSFER=${UPLOAD_WETRANSFER}" >> "$GITHUB_ENV"
	echo "UPLOAD_ALLKMOD=${UPLOAD_ALLKMOD}" >> "$GITHUB_ENV"
	echo "UPLOAD_SYSUPGRADE=${UPLOAD_SYSUPGRADE}" >> "$GITHUB_ENV"
	echo "USE_Cache=${USE_Cache}" >> "$GITHUB_ENV"

	for diy_script in "$DIY_SH" "$DIY_SH_AFB" "$DIY_SH_RFC"; do
		[ -f "$diy_script" ] && chmod +x "$diy_script"
	done
	echo "The Matrix_Target is: $Matrix_Target"
	echo "The MATH Matrix_Target is: $Target_CFG_Machine"
}
function init_openwrt_patch_2512() {
	case "$OpenWrt_PATCH_FILE_DIR" in
		openwrt-2512-ipq|openwrt-2410-ipq)
			;;
		*)
			device_config_error "This script only supports openwrt-2512-ipq or openwrt-2410-ipq"
			return 1
			;;
	esac
	if [ "$Firewall_Allow_WAN" = "1" ]; then
		sed -i '/^	commit$/i\
		set firewall.@zone[1].input="ACCEPT"
		' package/kochiya/autoset/files/def_uci/zzz-autoset*
		echo "----$Matrix_Target----wan-allow---"
		echo "WAN_NAME=_WAN_ALLOW" >> $GITHUB_ENV
	fi

	if [ "$TRY_BBR_V3" = "1" ]; then
		if ! kernel66_enabled; then
			device_config_error "BBR v3 requires KERNEL66=1"
			return 1
		fi
		local bbr_patch_dir
		if [ "$OpenWrt_PATCH_FILE_DIR" = "openwrt-2410-ipq" ]; then
			bbr_patch_dir="$OpenWrt_PATCH_FILE_DIR/mypatch-bbr-v3"
		else
			bbr_patch_dir="$OpenWrt_PATCH_FILE_DIR/mypatch-core-66/mypatch-bbr-v3"
		fi
		if [ ! -d "$bbr_patch_dir" ] || [ ! -d "$OpenWrt_PATCH_FILE_DIR/mypatch-core" ]; then
			device_config_error "BBR v3 patch directory is incomplete"
			return 1
		fi
		cp -f "$bbr_patch_dir"/*.patch "$OpenWrt_PATCH_FILE_DIR/mypatch-core/"
		echo "----$Matrix_Target----bbr-v3---"
		echo "TRY_BBR_V3_NAME=_BBR_V3" >> $GITHUB_ENV
	fi

	if [ "$OPENSSL_3_5" = "1" ]; then
		[ -d $OpenWrt_PATCH_FILE_DIR/openssl-bump ] && cp -r $OpenWrt_PATCH_FILE_DIR/openssl-bump/* $OpenWrt_PATCH_FILE_DIR/mypatch-custom-$Matrix_Target
		echo "----$Matrix_Target----openssl-3-5---"
		echo "OPENSSL_3_5_NAME=_OPENSSL_3_5" >> $GITHUB_ENV
	fi

	if [ "$MAC80211_616" = "1" ]; then
		[ -d $OpenWrt_PATCH_FILE_DIR/mac80211-616 ] && cp -r $OpenWrt_PATCH_FILE_DIR/mac80211-616/* $OpenWrt_PATCH_FILE_DIR/mypatch-custom-$Matrix_Target
		rm -rf openwrt/package/kernel/mt76/patches/100-api_compat.patch
		rm -rf openwrt/package/kernel/mac80211/patches/ath12k/002-wifi-ath12k-correctly-handle-mcast-packets-for-clien.patch
		rm -rf openwrt/package/kernel/mt76/patches/003-wifi-mt76-link_id.patch
		rm -rf openwrt/package/kernel/mt76/patches/100-api_update.patch
		echo "----$Matrix_Target----mac80211-6-16---"
		echo "MAC80211_616_NAME=_MAC80211_616" >> $GITHUB_ENV
	fi

	if [ "$BCM_FULLCONE" = "1" ] && [[ "$Matrix_Target" == *-iptables ]]; then
		[ -d $OpenWrt_PATCH_FILE_DIR/bcmfullcone ] && cp -r $OpenWrt_PATCH_FILE_DIR/bcmfullcone/a-* $OpenWrt_PATCH_FILE_DIR/mypatch-custom-$Matrix_Target
		rm -rf $OpenWrt_PATCH_FILE_DIR/feeds-luci-patch/0004-Revert-luci-app-firewall-add-fullcone.patch
		echo "----$Matrix_Target-----ipt-bcm---"
		echo "BCM_FULLCONE_NAME=_BCM_FULLCONE" >> $GITHUB_ENV
	fi

	if [ "$BCM_FULLCONE" = "1" ] && [[ "$Matrix_Target" == *-nftables ]]; then
		[ -d $OpenWrt_PATCH_FILE_DIR/bcmfullcone ] && cp -r $OpenWrt_PATCH_FILE_DIR/bcmfullcone/b-* $OpenWrt_PATCH_FILE_DIR/mypatch-custom-$Matrix_Target
		rm -rf $OpenWrt_PATCH_FILE_DIR/feeds-luci-patch/0004-Revert-luci-app-firewall-add-fullcone.patch
		echo "----$Matrix_Target-----nft-bcm---"
		echo "BCM_FULLCONE_NAME=_BCM_FULLCONE" >> $GITHUB_ENV
	fi

	if [ "$DOCKER_BUILDIN" = "1" ]; then
		for file0 in package-configs/$OpenWrt_PATCH_FILE_DIR/*.config; do     echo "# docker组件
CONFIG_PACKAGE_dockerd=y
CONFIG_PACKAGE_docker-compose=y
CONFIG_DOCKER_CHECK_CONFIG=y
CONFIG_DOCKER_CGROUP_OPTIONS=y
CONFIG_DOCKER_OPTIONAL_FEATURES=y
CONFIG_DOCKER_NET_OVERLAY=y
CONFIG_DOCKER_NET_ENCRYPT=y
CONFIG_DOCKER_NET_MACVLAN=y
CONFIG_DOCKER_NET_TFTP=y
CONFIG_DOCKER_STO_DEVMAPPER=y
CONFIG_DOCKER_STO_EXT4=y
CONFIG_DOCKER_STO_BTRFS=y
# end
CONFIG_PACKAGE_luci-app-dockerman=y
" >> "$file0"; done
		echo "----$Matrix_Target-----Docker--Config--Added--"
		echo "DOCKER_NAME=_DOCKER" >> $GITHUB_ENV
	fi

	if [ "$ADD_SDK" = "1" ]; then
		for file1 in package-configs/$OpenWrt_PATCH_FILE_DIR/*.config; do     echo "# ADD SDK
CONFIG_SDK=y
		" >> "$file1"; done
		echo "----------sdk-added------"
		echo "----$Matrix_Target----SDK---"
	fi

	if [ "$ADD_eBPF" = "1" ]; then
		for file1 in package-configs/$OpenWrt_PATCH_FILE_DIR/*.config; do     echo "# ADD eBPF
CONFIG_DEVEL=y
CONFIG_KERNEL_DEBUG_INFO=y
CONFIG_KERNEL_DEBUG_INFO_REDUCED=n
CONFIG_KERNEL_DEBUG_INFO_BTF=y
CONFIG_KERNEL_CGROUPS=y
CONFIG_KERNEL_CGROUP_BPF=y
CONFIG_KERNEL_BPF_EVENTS=y
CONFIG_BPF_TOOLCHAIN_HOST=y
CONFIG_KERNEL_XDP_SOCKETS=y
CONFIG_PACKAGE_kmod-xdp-sockets-diag=y
		" >> "$file1"; done
		echo "----------eBPF-added------"
		echo "eBPF=_eBPF" >> $GITHUB_ENV
		echo "----$Matrix_Target----eBPF---"
	fi

	if [ "${ADD_SKB_RECYCLER:-0}" = "1" ]; then
		for file1 in package-configs/$OpenWrt_PATCH_FILE_DIR/*.config; do
			grep -qx 'CONFIG_KERNEL_SKB_RECYCLER=y' "$file1" || echo 'CONFIG_KERNEL_SKB_RECYCLER=y' >> "$file1"
			grep -qx 'CONFIG_KERNEL_SKB_RECYCLER_MULTI_CPU=y' "$file1" || echo 'CONFIG_KERNEL_SKB_RECYCLER_MULTI_CPU=y' >> "$file1"
		done
		echo "----$Matrix_Target----SKB_RECYCLER---"
	fi

	if [ "$ADD_IB" = "1" ]; then
		for file2 in package-configs/$OpenWrt_PATCH_FILE_DIR/*.config; do     echo "# ADD SDK
CONFIG_IB=y
		" >> "$file2"; done
		echo "----$Matrix_Target----IB---"
	fi

	if kernel66_enabled; then
		echo "----$Matrix_Target----KERNEL-6.6---"
		set_testing_kernel_config
		echo "KERNEL66_NAME=_KERNEL66" >> $GITHUB_ENV
	fi

	if [ -n "${IPQ_Firmware:-}" ]; then
		local firmware_version
		case "$IPQ_Firmware" in
			ipq-nss-12-5) firmware_version=12_5 ;;
			ipq-nss-12-2) firmware_version=12_2 ;;
			ipq-nss-12-1) firmware_version=12_1 ;;
			ipq-nss-11-4) firmware_version=11_4 ;;
			*) firmware_version= ;;
		esac
		if [ -n "$firmware_version" ]; then
			for config_file in machine-configs/$OpenWrt_PATCH_FILE_DIR/*.config; do
				grep -qx "CONFIG_NSS_FIRMWARE_VERSION_${firmware_version}=y" "$config_file" || sed -i "1iCONFIG_NSS_FIRMWARE_VERSION_${firmware_version}=y" "$config_file"
				for other_version in 11_4 12_1 12_2 12_5; do
					[ "$other_version" = "$firmware_version" ] || sed -i "/^CONFIG_NSS_FIRMWARE_VERSION_${other_version}=/d" "$config_file"
				done
			done
			echo "----$Matrix_Target--IPQ--Firmware-${firmware_version//_}---"
		fi
	fi

}
function ln_openwrt() {
	sudo mkdir -p -m 777 /mnt/openwrt/dl /mnt/openwrt/bin /mnt/openwrt/staging_dir /mnt/openwrt/build_dir
	ln -sf /mnt/openwrt/dl openwrt/dl
	#ln -sf /mnt/openwrt/bin openwrt/bin
	#ln -sf /mnt/openwrt/staging_dir openwrt/staging_dir
	ln -sf /mnt/openwrt/build_dir openwrt/build_dir
	df -hT
	ls /mnt/openwrt
	echo "-------"
	ls -l openwrt | grep '^l'
	echo "-------"
	readlink openwrt
	echo "-------"
	ls -l /workdir/openwrt
}
function add_openwrt_ipq_sfe_66_compat() {
	local patch_root="$OpenWrt_PATCH_FILE_DIR/sfe-ipq-6.6"
	local target_dir="openwrt/target/linux/qualcommax/patches-6.6"
	local patch_file

	[ "$OpenWrt_PATCH_FILE_DIR" = "openwrt-2410-ipq" ] || return 0
	for patch_file in \
		"$patch_root/202603/0600-1-qca-nss-ecm-support-CORE.patch" \
		"$patch_root/202603/0603-1-qca-nss-clients-add-qdisc-support.patch" \
		"$patch_root/202601/0981-0-qca-skbuff-revert.patch"; do
		if [ ! -s "$patch_file" ]; then
			device_config_error "Missing IPQ SFE compatibility patch: $patch_file"
			return 1
		fi
	done

	mkdir -p "$target_dir"
	cp -f "$patch_root/202603/0600-1-qca-nss-ecm-support-CORE.patch" "$target_dir/"
	cp -f "$patch_root/202603/0603-1-qca-nss-clients-add-qdisc-support.patch" "$target_dir/"
	cp -f "$patch_root/202601/0981-0-qca-skbuff-revert.patch" "$target_dir/"
	mkdir -p openwrt/package/qca
}
function add_openwrt_ipq_sfe_612_compat() {
	local patch_root="$OpenWrt_PATCH_FILE_DIR/sfe-ipq-6.12"
	local target_dir="openwrt/target/linux/qualcommax/patches-6.12"
	local patch_file

	[ "$OpenWrt_PATCH_FILE_DIR" = "openwrt-2410-ipq" ] || return 0
	for patch_file in \
		"$patch_root/20250425/0600-1-qca-nss-ecm-support-CORE.patch" \
		"$patch_root/20250425/0981-0-qca-skbuff-revert.patch"; do
		if [ ! -s "$patch_file" ]; then
			device_config_error "Missing IPQ SFE compatibility patch: $patch_file"
			return 1
		fi
	done

	mkdir -p "$target_dir" openwrt/package/qca
	cp -f "$patch_root/20250425/0600-1-qca-nss-ecm-support-CORE.patch" "$target_dir/"
	cp -f "$patch_root/20250425/0981-0-qca-skbuff-revert.patch" "$target_dir/"
}
function copy_openwrt_turboacc_nft_packages() {
	local package_source="$1"
	local firewall4_version nftables_version libnftnl_version package_dir

	if [ ! -d "$package_source" ]; then
		device_config_error "TurboACC package source not found: $package_source"
		return 1
	fi
	for package_dir in nft-fullcone; do
		if [ ! -d "$package_source/$package_dir" ]; then
			device_config_error "Missing TurboACC nft package: $package_source/$package_dir"
			return 1
		fi
	done

	mkdir -p openwrt/package/turboacc
	cp -r "$package_source/nft-fullcone" openwrt/package/turboacc/ || return 1

	if [ ! -f openwrt/package/network/config/firewall4/Makefile ] || \
		[ ! -f openwrt/package/network/utils/nftables/Makefile ] || \
		[ ! -f openwrt/package/libs/libnftnl/Makefile ]; then
		device_config_error "OpenWrt nft package Makefiles are missing"
		return 1
	fi
	firewall4_version=$(grep -o 'PKG_SOURCE_VERSION:=.*' openwrt/package/network/config/firewall4/Makefile | cut -d '=' -f 2)
	nftables_version=$(grep -o 'PKG_VERSION:=.*' openwrt/package/network/utils/nftables/Makefile | cut -d '=' -f 2)
	libnftnl_version=$(grep -o 'PKG_VERSION:=.*' openwrt/package/libs/libnftnl/Makefile | cut -d '=' -f 2)

	if [ ! -d "$package_source/firewall4-$firewall4_version" ]; then
		firewall4_version=$(grep -o 'FIREWALL4_VERSION=.*' "$package_source/version" | cut -d '=' -f 2)
	fi
	if [ ! -d "$package_source/nftables-$nftables_version" ]; then
		nftables_version=$(grep -o 'NFTABLES_VERSION=.*' "$package_source/version" | cut -d '=' -f 2)
	fi
	if [ ! -d "$package_source/libnftnl-$libnftnl_version" ]; then
		libnftnl_version=$(grep -o 'LIBNFTNL_VERSION=.*' "$package_source/version" | cut -d '=' -f 2)
	fi

	for package_dir in \
		"firewall4-$firewall4_version/firewall4" \
		"nftables-$nftables_version/nftables" \
		"libnftnl-$libnftnl_version/libnftnl"; do
		if [ ! -d "$package_source/$package_dir" ]; then
			device_config_error "Missing TurboACC nft replacement: $package_source/$package_dir"
			return 1
		fi
	done

	rm -rf openwrt/package/libs/libnftnl \
		openwrt/package/network/config/firewall4 \
		openwrt/package/network/utils/nftables
	mkdir -p openwrt/package/libs openwrt/package/network/config openwrt/package/network/utils
	cp -RT "$package_source/firewall4-$firewall4_version/firewall4" openwrt/package/network/config/firewall4 || return 1
	cp -RT "$package_source/libnftnl-$libnftnl_version/libnftnl" openwrt/package/libs/libnftnl || return 1
	cp -RT "$package_source/nftables-$nftables_version/nftables" openwrt/package/network/utils/nftables || return 1
}
function add_openwrt_sfe_66_2512() {
	local config_name="${Target_CFG_Machine}-${Matrix_Target}.config"
	local config_file="package-configs/$OpenWrt_PATCH_FILE_DIR/$config_name"
	local kernel_config="openwrt/target/linux/generic/config-6.6"
	local turboacc_luci_commit="530092c532839efb96e9f328d34dbf3adff4b557"
	local turboacc_package_commit="c56760174a4b25e2a4f7566e3e4058e75e4ac9f8"
	local old_driver_hash="659fa82a431e15af797a6c7069faeee02810453ad8b576c51c29f95a1761a045"
	local driver_hash="0a73db82801fc0406a5bb7ff36e7e1b03f6550797b1aca0e8ea0cec3af465d2b"
	local temp_dir

	if [ ! -s "$config_file" ]; then
		device_config_error "Missing package config: $config_file"
		return 1
	fi
	if [ ! -f "$kernel_config" ]; then
		device_config_error "OpenWrt 6.6 kernel config not found: $kernel_config"
		return 1
	fi

	temp_dir="$(mktemp -d)" || return 1
	(
		trap 'rm -rf "$temp_dir"' EXIT
		mkdir -p "$temp_dir/package" openwrt/package \
			openwrt/target/linux/generic/pending-6.6 \
			openwrt/target/linux/generic/hack-6.6 || exit 1
		curl -fsSL "https://codeload.github.com/chenmozhijin/turboacc/tar.gz/$turboacc_package_commit" \
			-o "$temp_dir/package.tar.gz" || exit 1
		tar -xzf "$temp_dir/package.tar.gz" -C "$temp_dir/package" --strip-components=1 || exit 1

		rm -rf openwrt/package/shortcut-fe
		cp -r "$temp_dir/package/shortcut-fe" openwrt/package/ || exit 1
		sed -i "s/$old_driver_hash/$driver_hash/" \
			openwrt/package/shortcut-fe/simulated-driver/Makefile
		cp -f "$temp_dir/package/pending-6.6/613-netfilter_optional_tcp_window_check.patch" \
			openwrt/target/linux/generic/pending-6.6/ || exit 1
		cp -f "$temp_dir/package/hack-6.6/952-add-net-conntrack-events-support-multiple-registrant.patch" \
			openwrt/target/linux/generic/hack-6.6/ || exit 1
		cp -f "$temp_dir/package/hack-6.6/953-net-patch-linux-kernel-to-support-shortcut-fe.patch" \
			openwrt/target/linux/generic/hack-6.6/ || exit 1

		if [[ "$Matrix_Target" == *-nftables ]]; then
			mkdir -p "$temp_dir/luci" openwrt/package/turboacc || exit 1
			curl -fsSL "https://codeload.github.com/chenmozhijin/turboacc/tar.gz/$turboacc_luci_commit" \
				-o "$temp_dir/luci.tar.gz" || exit 1
			tar -xzf "$temp_dir/luci.tar.gz" -C "$temp_dir/luci" --strip-components=1 || exit 1
			rm -rf openwrt/package/turboacc/luci-app-turboacc
			cp -r "$temp_dir/luci/luci-app-turboacc" openwrt/package/turboacc/ || exit 1
			copy_openwrt_turboacc_nft_packages "$temp_dir/package" || exit 1
		fi
	) || return 1

	grep -q 'CONFIG_NF_CONNTRACK_CHAIN_EVENTS' "$kernel_config" || \
		echo '# CONFIG_NF_CONNTRACK_CHAIN_EVENTS is not set' >> "$kernel_config"
	grep -q 'CONFIG_SHORTCUT_FE' "$kernel_config" || \
		echo '# CONFIG_SHORTCUT_FE is not set' >> "$kernel_config"

	if [[ "$Matrix_Target" == *-iptables ]]; then
		if ! grep -q '^CONFIG_PACKAGE_luci-app-turboacc-ipt=y$' "$config_file"; then
			cat >> "$config_file" <<'EOF'

# SFE acceleration for kernel 6.6 (iptables)
CONFIG_PACKAGE_luci-app-turboacc-ipt=y
# CONFIG_PACKAGE_luci-app-turboacc-ipt_INCLUDE_PDNSD is not set
CONFIG_PACKAGE_kmod-ipt-offload=y
CONFIG_PACKAGE_kmod-fast-classifier=y
CONFIG_PACKAGE_kmod-shortcut-fe=y
# CONFIG_PACKAGE_kmod-shortcut-fe-cm is not set
EOF
		fi
	elif [[ "$Matrix_Target" == *-nftables ]]; then
		if ! grep -q '^CONFIG_PACKAGE_luci-app-turboacc=y$' "$config_file"; then
			cat >> "$config_file" <<'EOF'

# SFE acceleration for kernel 6.6 (nftables)
CONFIG_PACKAGE_luci-app-turboacc=y
# CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_OFFLOADING is not set
CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_SHORTCUT_FE=y
# CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_SHORTCUT_FE_CM is not set
# CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_SHORTCUT_FE_DRV is not set
CONFIG_PACKAGE_kmod-nft-offload=y
CONFIG_PACKAGE_kmod-fast-classifier=y
CONFIG_PACKAGE_kmod-shortcut-fe=y
# CONFIG_PACKAGE_kmod-shortcut-fe-cm is not set
CONFIG_PACKAGE_kmod-nft-fullcone=y
EOF
		fi
	else
		device_config_error "Unsupported SFE matrix target: $Matrix_Target"
		return 1
	fi

	add_openwrt_ipq_sfe_66_compat || return 1
	add_openwrt_sfe_kmods
	echo "----$Matrix_Target-----SFE-6.6----"
}
function add_openwrt_sfe_612_2512() {
	local config_name="${Target_CFG_Machine}-${Matrix_Target}.config"
	local config_file="package-configs/$OpenWrt_PATCH_FILE_DIR/$config_name"
	local kernel_config="openwrt/target/linux/generic/config-6.12"
	local turboacc_luci_commit="530092c532839efb96e9f328d34dbf3adff4b557"
	local turboacc_package_commit="c56760174a4b25e2a4f7566e3e4058e75e4ac9f8"
	local temp_dir

	if [ "$OpenWrt_PATCH_FILE_DIR" != "openwrt-2512-ipq" ] && [ "$OpenWrt_PATCH_FILE_DIR" != "openwrt-2410-ipq" ]; then
		device_config_error "add-openwrt-sfe-2512 requires openwrt-2512-ipq or openwrt-2410-ipq"
		return 1
	fi
	if [[ "$Matrix_Target" != *-iptables && "$Matrix_Target" != *-nftables ]]; then
		device_config_error "Unsupported SFE matrix target: $Matrix_Target"
		return 1
	fi
	if [ ! -s "$config_file" ]; then
		device_config_error "Missing package config: $config_file"
		return 1
	fi
	if [ ! -f "$kernel_config" ]; then
		device_config_error "OpenWrt 6.12 kernel config not found: $kernel_config"
		return 1
	fi

	temp_dir="$(mktemp -d)" || return 1
	(
		trap 'rm -rf "$temp_dir"' EXIT
		mkdir -p "$temp_dir/luci" "$temp_dir/package" \
			openwrt/package/turboacc \
			openwrt/target/linux/generic/pending-6.12 \
			openwrt/target/linux/generic/hack-6.12 || exit 1
		curl -fsSL "https://codeload.github.com/chenmozhijin/turboacc/tar.gz/$turboacc_luci_commit" \
			-o "$temp_dir/luci.tar.gz" || exit 1
		curl -fsSL "https://codeload.github.com/chenmozhijin/turboacc/tar.gz/$turboacc_package_commit" \
			-o "$temp_dir/package.tar.gz" || exit 1
		tar -xzf "$temp_dir/luci.tar.gz" -C "$temp_dir/luci" --strip-components=1 || exit 1
		tar -xzf "$temp_dir/package.tar.gz" -C "$temp_dir/package" --strip-components=1 || exit 1

		rm -rf openwrt/package/turboacc/luci-app-turboacc openwrt/package/turboacc/shortcut-fe
		cp -r "$temp_dir/luci/luci-app-turboacc" openwrt/package/turboacc/ || exit 1
		cp -r "$temp_dir/package/shortcut-fe" openwrt/package/turboacc/ || exit 1
		rm -rf openwrt/package/turboacc/shortcut-fe/simulated-driver
		if [[ "$Matrix_Target" == *-nftables ]]; then
			copy_openwrt_turboacc_nft_packages "$temp_dir/package" || exit 1
		fi

		cp -f "$temp_dir/package/pending-6.12/613-netfilter_optional_tcp_window_check.patch" \
			openwrt/target/linux/generic/pending-6.12/ || exit 1
		cp -f "$temp_dir/package/hack-6.12/952-add-net-conntrack-events-support-multiple-registrant.patch" \
			openwrt/target/linux/generic/hack-6.12/ || exit 1
		cp -f "$temp_dir/package/hack-6.12/953-net-patch-linux-kernel-to-support-shortcut-fe.patch" \
			openwrt/target/linux/generic/hack-6.12/ || exit 1
	) || return 1

	grep -q 'CONFIG_NF_CONNTRACK_CHAIN_EVENTS' "$kernel_config" || \
		echo '# CONFIG_NF_CONNTRACK_CHAIN_EVENTS is not set' >> "$kernel_config"
	grep -q 'CONFIG_SHORTCUT_FE' "$kernel_config" || \
		echo '# CONFIG_SHORTCUT_FE is not set' >> "$kernel_config"

	if [[ "$Matrix_Target" == *-iptables ]]; then
		if ! grep -q '^CONFIG_PACKAGE_luci-app-turboacc-ipt=y$' "$config_file"; then
			cat >> "$config_file" <<'EOF'

# SFE acceleration for kernel 6.12 (iptables)
CONFIG_PACKAGE_luci-app-turboacc-ipt=y
# CONFIG_PACKAGE_luci-app-turboacc-ipt_INCLUDE_PDNSD is not set
# CONFIG_PACKAGE_luci-app-turboacc-ipt_INCLUDE_OFFLOADING is not set
CONFIG_PACKAGE_luci-app-turboacc-ipt_INCLUDE_SHORTCUT_FE=y
# CONFIG_PACKAGE_luci-app-turboacc-ipt_INCLUDE_SHORTCUT_FE_CM is not set
# CONFIG_PACKAGE_luci-app-turboacc-ipt_INCLUDE_SHORTCUT_FE_DRV is not set
CONFIG_PACKAGE_luci-app-turboacc-ipt_INCLUDE_BBR_CCA=y
# CONFIG_PACKAGE_luci-app-turboacc-ipt_INCLUDE_IPT_FULLCONE is not set
CONFIG_PACKAGE_kmod-fast-classifier=y
CONFIG_PACKAGE_kmod-shortcut-fe=y
# CONFIG_PACKAGE_kmod-shortcut-fe-cm is not set
EOF
		fi
	elif [[ "$Matrix_Target" == *-nftables ]]; then
		if ! grep -q '^CONFIG_PACKAGE_luci-app-turboacc=y$' "$config_file"; then
			cat >> "$config_file" <<'EOF'

# SFE acceleration for kernel 6.12 (nftables)
CONFIG_PACKAGE_luci-app-turboacc=y
# CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_OFFLOADING is not set
CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_SHORTCUT_FE=y
# CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_SHORTCUT_FE_CM is not set
# CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_SHORTCUT_FE_DRV is not set
CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_BBR_CCA=y
CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_NFT_FULLCONE=y
CONFIG_PACKAGE_kmod-nft-offload=y
CONFIG_PACKAGE_kmod-fast-classifier=y
CONFIG_PACKAGE_kmod-shortcut-fe=y
# CONFIG_PACKAGE_kmod-shortcut-fe-cm is not set
CONFIG_PACKAGE_kmod-nft-fullcone=y
EOF
		fi
	else
		device_config_error "Unsupported SFE matrix target: $Matrix_Target"
		return 1
	fi

	add_openwrt_ipq_sfe_612_compat || return 1
	add_openwrt_sfe_kmods
	echo "----$Matrix_Target-----SFE-6.12----"
}
function add_openwrt_sfe_2512() {
	if kernel66_enabled; then
		add_openwrt_sfe_66_2512
	else
		add_openwrt_sfe_612_2512
	fi
}
function add_openwrt_nosfe_ipq_2512() {
	local config_name="${Target_CFG_Machine}-${Matrix_Target}.config"
	local config_file="package-configs/$OpenWrt_PATCH_FILE_DIR/$config_name"

	if [ "$OpenWrt_PATCH_FILE_DIR" != "openwrt-2410-ipq" ]; then
		device_config_error "add-openwrt-nosfe-ipq-2512 requires openwrt-2410-ipq"
		return 1
	fi
	if [ ! -s "$config_file" ]; then
		device_config_error "Missing package config: $config_file"
		return 1
	fi

	mkdir -p openwrt/package/qca
	if [[ "$Matrix_Target" == *-iptables ]]; then
		if ! grep -q '^CONFIG_PACKAGE_luci-app-turboacc-ipt=y$' "$config_file"; then
			cat >> "$config_file" <<'EOF'

# TurboACC without SFE (iptables)
CONFIG_PACKAGE_luci-app-turboacc-ipt=y
# CONFIG_PACKAGE_luci-app-turboacc-ipt_INCLUDE_PDNSD is not set
# CONFIG_PACKAGE_luci-app-turboacc-ipt_INCLUDE_SHORTCUT_FE_DRV is not set
EOF
		fi
		[ -n "${DIY_SH:-}" ] && [ -f "$DIY_SH" ] && \
			sed -i 's/"feeds\/lunatic7\/shortcut-fe"//g' "$DIY_SH"
	elif [[ "$Matrix_Target" == *-nftables ]]; then
		if ! grep -q '^CONFIG_PACKAGE_luci-app-turboacc=y$' "$config_file"; then
			cat >> "$config_file" <<'EOF'

# TurboACC without SFE (nftables)
CONFIG_PACKAGE_luci-app-turboacc=y
# CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_PDNSD is not set
# CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_SHORTCUT_FE_DRV is not set
EOF
		fi
		if [ -n "${DIY_SH:-}" ] && [ -f "$DIY_SH" ]; then
			sed -i 's/"feeds\/lunatic7\/luci-app-turboacc"//g' "$DIY_SH"
			sed -i 's/"feeds\/lunatic7\/shortcut-fe"//g' "$DIY_SH"
		fi
	else
		device_config_error "Unsupported non-SFE matrix target: $Matrix_Target"
		return 1
	fi
	echo "----$Matrix_Target-----TurboACC-without-SFE----"
}
function add_openwrt_ipq_sfe_feed_66_compat() {
	local patch_source="$OpenWrt_PATCH_FILE_DIR/sfe-ipq-6.6/qca-nss-ecm/patches/1001-ecm-support-conntrack-chain-events.patch"
	local patch_dir="openwrt/feeds/nss_packages/qca-nss-ecm/patches"

	[ "$OpenWrt_PATCH_FILE_DIR" = "openwrt-2410-ipq" ] || return 0
	kernel66_enabled || return 0
	[ "${SFE_INPUT_STATUS:-false}" = "true" ] || return 0
	if [ ! -s "$patch_source" ]; then
		device_config_error "Missing qca-nss-ecm SFE compatibility patch: $patch_source"
		return 1
	fi
	if [ ! -d "$patch_dir" ]; then
		device_config_error "qca-nss-ecm feed is missing: $patch_dir"
		return 1
	fi
	cp -f "$patch_source" "$patch_dir/"
}
function add_openwrt_sfe_kmods() {
	sed -i 's/kmod-shortcut-fe-cm,kmod-shortcut-fe,kmod-fast-classifier,kmod-fast-classifier-noload,kmod-shortcut-fe-drv,//g' package-configs/kmod_exclude_list*
}
function add_openwrt_files() {
	mkdir -p openwrt/feeds/lunatic7
	if [ "$OpenWrt_REPO_ENV_FILE" = "openwrt-2512-ipq" ]; then
	mv -f openwrt-2512-ipq/mypatch-core/0001-tools-add-liblzo-dependency-to-ccache.patch openwrt-2410-ipq/mypatch-core/0001-tools-add-liblzo-dependency-to-ccache.patch
	fi
	mkdir -p openwrt/package/firmware/ipq-wifi/src
	# [ -d $OpenWrt_PATCH_FILE_DIR/bin-files ] && cp -r $OpenWrt_PATCH_FILE_DIR/bin-files/ipq-wifi/src/* openwrt/package/firmware/ipq-wifi/src
	[ -d package ] && cp -r package/* openwrt/package
	[ -d $OpenWrt_PATCH_FILE_DIR/package-for-$OpenWrt_PATCH_FILE_DIR ] && cp -r $OpenWrt_PATCH_FILE_DIR/package-for-$OpenWrt_PATCH_FILE_DIR/* openwrt/package
	[ -d $OpenWrt_PATCH_FILE_DIR/mypatch-core ] && mv -f $OpenWrt_PATCH_FILE_DIR/mypatch-core openwrt/mypatch-core
	[ -d $OpenWrt_PATCH_FILE_DIR/mypatch-custom-$Matrix_Target ] && mv -f $OpenWrt_PATCH_FILE_DIR/mypatch-custom-$Matrix_Target openwrt/mypatch-custom

	[ -e files ] && mv files openwrt/files
}
function apply_openwrt_patch_dir() {
	local patch_dir="$1"
	local patch_file
	local -a patch_files

	if [ ! -d "$patch_dir" ]; then
		echo "No $patch_dir directory, skipping"
		return 0
	fi

	shopt -s nullglob
	patch_files=("$patch_dir"/*.patch)
	shopt -u nullglob
	for patch_file in "${patch_files[@]}"; do
		if [ "$OpenWrt_REPO_ENV_FILE" = "openwrt-2512-ipq" ]; then
			case "${patch_file##*/}" in
				0001-generic-138-139-fix-in-6.6.patch|0001-ipq807x-add-support-for-Aliyun-AP8220-mod-for-ipq-24.patch|0003-CVE-2026-31431-FIX.patch)
					echo "Skipping already included IPQ 25.12 patch: $patch_file"
					continue
					;;
			esac
		fi
		echo "Applying $patch_file"
		patch -p1 --no-backup-if-mismatch --quiet < "$patch_file" || return 1
	done
}
function patch_openwrt_core() {
	apply_openwrt_patch_dir mypatch-core
}
function patch_openwrt_custom() {
	apply_openwrt_patch_dir mypatch-custom
}
function patch_openwrt_core_pre() {
	cd openwrt || return 1
	patch_openwrt_core || return 1
	patch_openwrt_custom || return 1
	cd ../
}
function fix_openwrt_feeds() {
	add_openwrt_ipq_sfe_feed_66_compat || return 1
	# [ -e package-configs ] && cp -r package-configs openwrt/package-configs
	[ -d $OpenWrt_PATCH_FILE_DIR/lunatic7-revert ] && mv -f $OpenWrt_PATCH_FILE_DIR/lunatic7-revert openwrt/feeds/lunatic7/lunatic7-revert
	[ -d $OpenWrt_PATCH_FILE_DIR/feeds-luci-patch ] && mv -f $OpenWrt_PATCH_FILE_DIR/feeds-luci-patch openwrt/feeds/luci/feeds-luci-patch
	[ -d $OpenWrt_PATCH_FILE_DIR/feeds-packages-patch ] && mv -f $OpenWrt_PATCH_FILE_DIR/feeds-packages-patch openwrt/feeds/packages/feeds-packages-patch
	[ -d $OpenWrt_PATCH_FILE_DIR/feeds-telephony-patch ] && mv -f $OpenWrt_PATCH_FILE_DIR/feeds-telephony-patch openwrt/feeds/telephony/feeds-telephony-patch
	[ -d $OpenWrt_PATCH_FILE_DIR/feeds-routing-patch ] && mv -f $OpenWrt_PATCH_FILE_DIR/feeds-routing-patch openwrt/feeds/routing/feeds-routing-patch

	if [ "$OpenWrt_REPO_ENV_FILE" = "openwrt-2512-ipq" ]; then
	rm -rf openwrt/feeds/lunatic7/lunatic7-revert openwrt/feeds/luci/feeds-luci-patch openwrt/feeds/packages/feeds-packages-patch openwrt/feeds/telephony/feeds-telephony-patch openwrt/feeds/routing/feeds-routing-patch
	[ -d openwrt-2512-ipq/lunatic7-revert ] && mv -f openwrt-2512-ipq/lunatic7-revert openwrt/feeds/lunatic7/lunatic7-revert
	[ -d openwrt-2512-ipq/feeds-luci-patch ] && mv -f openwrt-2512-ipq/feeds-luci-patch openwrt/feeds/luci/feeds-luci-patch
	[ -d openwrt-2512-ipq/feeds-packages-patch ] && mv -f openwrt-2512-ipq/feeds-packages-patch openwrt/feeds/packages/feeds-packages-patch
	[ -d openwrt-2512-ipq/feeds-telephony-patch ] && mv -f openwrt-2512-ipq/feeds-telephony-patch openwrt/feeds/telephony/feeds-telephony-patch
	[ -d openwrt-2512-ipq/feeds-routing-patch ] && mv -f openwrt-2512-ipq/feeds-routing-patch openwrt/feeds/routing/feeds-routing-patch
	fi
	cd openwrt
	autosetver_2512
	remove_error_package_not_install
	patch_openwrt_feeds
	patch_lunatic7
	change_qca_start_order
	if [ "$Matrix_Target" == 'ramips-iptables' ] || [ "$Matrix_Target" == 'ramips-nftables' ] || \
		[ "$Matrix_Target" == 'ath79-iptables' ] || [ "$Matrix_Target" == 'ath79-nftables' ]; then
		rm -rf feeds/lunatic7/luci-app-cupsd/root/www/cups.pdf
		fi

	cd ../
	add_machine_package_config
}
function autosetver_2512() {
	# 在文件的 'exit 0' 之前插入 DISTRIB_DESCRIPTION 信息
	sed -i "/^exit 0$/i\
	\echo \"DISTRIB_DESCRIPTION='OpenWrt 25.12 Compiled by 2U4U'\" >> /etc/openwrt_release
	" package/kochiya/autoset/files/def_uci/zzz-autoset*

	# 使用通配符匹配所有以 zzz-autoset- 开头的文件并执行 grep
	for file in package/kochiya/autoset/files/def_uci/zzz-autoset-*; do
		grep DISTRIB_DESCRIPTION "$file"
	done
}
function add_machine_package_config() {
	local config_name="${Target_CFG_Machine}-${Matrix_Target}.config"
	local machine_config="machine-configs/$OpenWrt_PATCH_FILE_DIR/$config_name"
	local package_config="package-configs/$OpenWrt_PATCH_FILE_DIR/$config_name"

	if [ ! -s "$machine_config" ]; then
		device_config_error "Missing machine config: $machine_config"
		return 1
	fi
	if [ ! -s "$package_config" ]; then
		device_config_error "Missing package config: $package_config"
		return 1
	fi

	cat "$machine_config" "$package_config" >> openwrt/.config
	if [[ "$Matrix_Target" == *-iptables ]]; then
		cat >> openwrt/.config <<'EOF'
CONFIG_PACKAGE_firewall=y
# CONFIG_PACKAGE_firewall4 is not set
EOF
	fi
}
function change_qca_start_order() {

NSS_DRV="feeds/nss_packages/qca-nss-drv/files/qca-nss-drv.init"
if [ -f "$NSS_DRV" ]; then
	sed -i 's/START=.*/START=85/g' $NSS_DRV

	echo "qca-nss-drv has been fixed!"
fi

NSS_PBUF="package/kernel/mac80211/files/qca-nss-pbuf.init"
if [ -f "$NSS_PBUF" ]; then
	sed -i 's/START=.*/START=86/g' $NSS_PBUF

	echo "qca-nss-pbuf has been fixed!"
fi
}
function patch_openwrt_feeds() {
    for packagepatch in $( ls feeds/packages/feeds-packages-patch ); do
        cd feeds/packages/
        echo Applying feeds-packages-patch $packagepatch
        patch -p1 --no-backup-if-mismatch < feeds-packages-patch/$packagepatch
        cd ../..
    done

    for lucipatch in $( ls feeds/luci/feeds-luci-patch ); do
        cd feeds/luci/
        echo Applying feeds-luci-patch $lucipatch
        patch -p1 --no-backup-if-mismatch < feeds-luci-patch/$lucipatch
        cd ../..
    done

    for telepatch in $( ls feeds/telephony/feeds-telephony-patch ); do
    cd feeds/telephony/
    echo Applying feeds-telephony-patch $telepatch
        patch -p1 --no-backup-if-mismatch < feeds-telephony-patch/$telepatch
    cd ../..
    done

    for routingpatch in $( ls feeds/routing/feeds-routing-patch ); do
    cd feeds/routing/
    echo Applying feeds-routing-patch $routingpatch
        patch -p1 --no-backup-if-mismatch --quiet < feeds-routing-patch/$routingpatch
    cd ../..
    done
}
function patch_lunatic7() {
    for lunatic7patch in $( ls feeds/lunatic7/lunatic7-revert ); do
        cd feeds/lunatic7/
        echo Revert lunatic7 $lunatic7patch
        patch -p1 -R --no-backup-if-mismatch < lunatic7-revert/$lunatic7patch
        cd ../..
    done
}
function remove_error_package_not_install() {
	packages=(
		"luci-app-smartdns"
		"rtl8821cu"
		"xray-core"
		"smartdns"
		"luci-app-filebrowser"
		"luci-app-filemanager"
	)

	for package in "${packages[@]}"; do
		echo "卸载软件包 $package ..."
		./scripts/feeds uninstall $package
		echo "软件包 $package 已卸载。"
	done

	directories=(
		"feeds/luci/applications/luci-app-smartdns"
		"feeds/luci/applications/luci-app-filebrowser"
		"feeds/luci/applications/luci-app-filemanager"
		"feeds/lunatic7/rtl8821cu"
		"feeds/lunatic7/shortcut-fe"
		"feeds/lunatic7/fullconenat-nft"
		"feeds/lunatic7/luci-app-turboacc"
		"feeds/packages/net/xray-core"
		"feeds/packages/net/smartdns"
	)

	for directory in "${directories[@]}"; do
	if [ -d "$directory" ]; then
		echo "目录 $directory 存在，进行删除操作..."
		rm -r "$directory"
		echo "目录 $directory 已删除。"
	else
		echo "目录 $directory 不存在。"
	fi
	done

	echo "升级索引"
	./scripts/feeds update -i

	for package2 in "${packages[@]}"; do
		echo "安装软件包 $package2 ..."
		./scripts/feeds install $package2
		echo "软件包 $package2 已经重新安装。"
	done
}
function refine_openwrt_config() {
cd openwrt
IFS=',' read -r -a package_array <<< "$INPUT_PKGS_CFG_FOO"
for pkg in "${package_array[@]}"; do
    ./scripts/feeds install "$pkg"

    if [ "$INPUT_PKGS_CFG_STATUS" = "y" ]; then
        echo "CONFIG_PACKAGE_$pkg=y" >> .config
        echo "$pkg Added ..."
    elif [ "$INPUT_PKGS_CFG_STATUS" = "m" ]; then
        echo "CONFIG_PACKAGE_$pkg=m" >> .config
        echo "$pkg Marked ..."
    elif [ "$INPUT_PKGS_CFG_STATUS" = "n" ]; then
        echo "CONFIG_PACKAGE_$pkg=n" >> .config
        echo "$pkg Remove ..."
    fi
done

make defconfig

for pkg in "${package_array[@]}"; do
    awk -v pkg="$pkg" '$0 ~ pkg { print }' .config
done

cd ../
fix_openwrt_config_eror
}
function add_all_kmod_config() {

if [[ "$Matrix_Target" == ramips-* ]]; then
KMOD_Compile_Exclude_List_Route=package-configs/kmod_exclude_list_ramips.config
echo "The exclude List route is $KMOD_Compile_Exclude_List_Route"
elif [[ "$Matrix_Target" == ath79-* ]]; then
KMOD_Compile_Exclude_List_Route=package-configs/kmod_exclude_list_ath79.config
echo "The exclude List route is $KMOD_Compile_Exclude_List_Route"
elif [[ "$Matrix_Target" == ipq-* ]]; then
KMOD_Compile_Exclude_List_Route=package-configs/kmod_exclude_list_ipq.config
echo "The exclude List route is $KMOD_Compile_Exclude_List_Route"
elif [ "$KERNEL66" = "1" ]; then
KMOD_Compile_Exclude_List_Route=package-configs/kmod_exclude_list_6_12.config
echo "The exclude List route is $KMOD_Compile_Exclude_List_Route"
else
KMOD_Compile_Exclude_List_Route=package-configs/kmod_exclude_list.config
echo "The exclude List route is $KMOD_Compile_Exclude_List_Route"
fi
all_kmod_config_core
}
function all_kmod_config_core() {
if [ -n "$(sed -n '/^kmod_compile_exclude_list=/p' $KMOD_Compile_Exclude_List_Route | sed -e "s/=[my]\([,]\{0,1\}\)/\1/g" -e 's/.*=//')" ];then
  kmod_compile_exclude_list=$(sed -n '/^kmod_compile_exclude_list=/p' $KMOD_Compile_Exclude_List_Route | sed -e "s/=[my]\([,]\{0,1\}\)/\1/g" -e 's/.*=//' -e 's/,$//g' -e 's#^#\\(#' -e "s#,#\\\|#g" -e "s/$/\\\)/g" )
  echo "::notice ::编译排除列表：$(sed -n '/^kmod_compile_exclude_list=/p' $KMOD_Compile_Exclude_List_Route | sed -e "s/=[my]\([,]\{0,1\}\)/\1/g" -e 's/.*=//')"
else
  echo "::warning ::kmod编译排除列表无法获取或为空，这很有可能导致编译失败。"
fi
sed -n  '/^# CONFIG_PACKAGE_kmod/p' openwrt/.config | sed '/# CONFIG_PACKAGE_kmod is not set/d'|sed 's/# //g'|sed 's/ is not set/=m/g' | sed "s/\($kmod_compile_exclude_list\)=m/\1=n/g" >> openwrt/.config
echo "::notice ::当前内核版本$(grep CONFIG_LINUX openwrt/.config | cut -d'=' -f1 | cut -d'_' -f3-)"
}
function fix_openwrt_config_eror() {
if [[ "$Matrix_Target" == *iptables ]]; then
sed -i 's/CONFIG_PACKAGE_perl-test-harness=y/# CONFIG_PACKAGE_perl-test-harness is not set/g' openwrt/.config
sed -i 's/# CONFIG_PACKAGE_libustream-openssl is not set/CONFIG_PACKAGE_libustream-openssl=y/g' openwrt/.config
sed -i 's/CONFIG_PACKAGE_nftables-json=y/# CONFIG_PACKAGE_nftables-json is not set/g' openwrt/.config
sed -i 's/CONFIG_PACKAGE_kmod-nft-offload=y/# CONFIG_PACKAGE_kmod-nft-offload is not set/g' openwrt/.config
sed -i 's/CONFIG_PACKAGE_qBittorrent-static=y/# CONFIG_PACKAGE_qBittorrent-static is not set/g' openwrt/.config
fi
if [[ "$Matrix_Target" == *nftables ]]; then
sed -i 's/CONFIG_PACKAGE_perl-test-harness=y/# CONFIG_PACKAGE_perl-test-harness is not set/g' openwrt/.config
sed -i 's/# CONFIG_PACKAGE_libustream-openssl is not set/CONFIG_PACKAGE_libustream-openssl=y/g' openwrt/.config
sed -i 's/CONFIG_PACKAGE_qBittorrent-static=y/# CONFIG_PACKAGE_qBittorrent-static is not set/g' openwrt/.config
fi
}
function add_openwrt_kmods() {
	add_all_kmod_config
	cd openwrt && make defconfig && cd ../
	add_all_kmod_config
	cd openwrt && make defconfig && cd ../
	add_all_kmod_config
	cd openwrt && make defconfig && cd ../
	fix_openwrt_config_eror
}
function awk_openwrt_config() {
	echo "------------------------"
	awk '/CONFIG_LINUX/ { print }' .config
	awk '/'"$Matrix_Target"'/ { print }' .config
	echo "------------------------"
	awk '/'"$Target_CFG_Machine"'/ { print }' .config
	echo "------------------------"
	awk '/mediatek/ { print }' .config
	echo "------------------------"
	awk '/wpad/ { print }' .config
	echo "------------------------"
	awk '/docker/ { print }' .config
	echo "------------------------"
	awk '/DOCKER/ { print }' .config
	echo "------------------------"
	awk '/store/ { print }' .config
	echo "------------------------"
	awk '/perl/ { print }' .config
	echo "------------------------"
	awk '/dnsmasq/ { print }' .config
	echo "------------------------"
	awk '/CONFIG_PACKAGE_kmod/ { print }' .config
	echo "------------------------"
	awk '/mt7981/ { print }' .config
	echo "------------------------"
	awk '/turboacc/ { print }' .config
}

case "${1:-}" in
	resolve-build-matrix)
		resolve_build_matrix
		;;
	init-pkg-env)
		init_pkg_env
		;;
	init-gh-env)
		init_gh_env_2512
		config_json_input_set
		patch_json_input_set
		init_gh_env_common
		;;
	init-openwrt-patch)
		init_openwrt_patch_2512
		;;
	ln-openwrt)
		ln_openwrt
		;;
	add-openwrt-sfe-2512)
		add_openwrt_sfe_2512
		;;
	add-openwrt-nosfe-ipq-2512)
		add_openwrt_nosfe_ipq_2512
		;;
	add-openwrt-files)
		add_openwrt_files
		patch_openwrt_core_pre || exit 1
		;;
	add-openwrt-kmods)
		add_openwrt_kmods
		;;
	fix-openwrt-feeds)
		fix_openwrt_feeds
		refine_openwrt_config
		;;
	awk-openwrt-config)
		awk_openwrt_config
		;;
	*)
		echo "Usage: $0 {resolve-build-matrix|init-pkg-env|init-gh-env|init-openwrt-patch|ln-openwrt|add-openwrt-sfe-2512|add-openwrt-nosfe-ipq-2512|add-openwrt-files|add-openwrt-kmods|fix-openwrt-feeds|awk-openwrt-config}" >&2
		exit 1
		;;
esac
