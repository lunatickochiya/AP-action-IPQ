#!/bin/bash
#=================================================
# This script is from https://github.com/lunatickochiya/Lunatic-s805-rockchip-Action
# Written By lunatickochiya
# QQ group :286754582  https://jq.qq.com/?_wv=1027&k=5QgVYsC
#=================================================

function init_openwrt_patch_file_dir_2410() {
OpenWrt_PATCH_FILE_DIR="openwrt-2410"
}

function init_openwrt_patch_file_dir_2410_nss() {
OpenWrt_PATCH_FILE_DIR="openwrt-2410-ipq"
}

function device_config_error() {
	echo "::error title=Device config error::$*" >&2
	return 1
}

# Resolve <machine>-<target>-{iptables,nftables}.config into a build matrix.
# Adding a device only requires matching files in machine-configs and package-configs.
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

function init_gh_env_2410() {
	source "${GITHUB_WORKSPACE}/env/common.txt"
	source "${GITHUB_WORKSPACE}/env/$OpenWrt_PATCH_FILE_DIR.repo"
	echo -e "TEST_KERNEL=$(echo $PATCH_JSON_INPUT | jq -r ".TEST_KERNEL")" >> "$GITHUB_ENV"
	echo -e "ADD_eBPF=$(echo $PATCH_JSON_INPUT | jq -r ".ADD_eBPF")" >> "$GITHUB_ENV"
}

function init_gh_env_2410_ipq() {
	source "${GITHUB_WORKSPACE}/env/common.txt"
	source "${GITHUB_WORKSPACE}/env/$OpenWrt_PATCH_FILE_DIR.repo"
	echo -e "Branch=$(echo $PATCH_JSON_INPUT | jq -r ".Branch")" >> $GITHUB_ENV
	echo -e "IPQ_Firmware=$(echo $PATCH_JSON_INPUT | jq -r ".IPQ_Firmware")" >> $GITHUB_ENV
	echo -e "ADD_eBPF=$(echo $PATCH_JSON_INPUT | jq -r ".ADD_eBPF")" >> "$GITHUB_ENV"
	echo -e "ADD_SKB_RECYCLER=$(echo $PATCH_JSON_INPUT | jq -r ".ADD_SKB_RECYCLER")" >> "$GITHUB_ENV"
}

function init_gh_env_by_config_set() {
	case "$OpenWrt_PATCH_FILE_DIR" in
		openwrt-2410-ipq)
			init_gh_env_2410_ipq
			;;
		*)
			init_gh_env_2410
			;;
	esac
	config_json_input_set
	patch_json_input_set
	init_gh_env_common
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

function init_openwrt_patch_common() {
	if [ "$Firewall_Allow_WAN" = "1" ]; then
		sed -i '/^	commit$/i\
		set firewall.@zone[1].input="ACCEPT"
		' package/kochiya/autoset/files/def_uci/zzz-autoset*
		echo "----$Matrix_Target----wan-allow---"
		echo "WAN_NAME=_WAN_ALLOW" >> $GITHUB_ENV
	fi

	if [ "$TRY_BBR_V3" = "1" ]; then
		[ -d $OpenWrt_PATCH_FILE_DIR/mypatch-bbr-v3 ] && cp -r $OpenWrt_PATCH_FILE_DIR/mypatch-bbr-v3/* $OpenWrt_PATCH_FILE_DIR/mypatch-custom-$Matrix_Target
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

	if [ "$AG71XX_FIX" = "1" ]; then
		[ -d $OpenWrt_PATCH_FILE_DIR/my-patch-ag71xx-fix ] && cp -r $OpenWrt_PATCH_FILE_DIR/my-patch-ag71xx-fix/* $OpenWrt_PATCH_FILE_DIR/mypatch-custom-$Matrix_Target
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

	if [ "$ADD_SKB_RECYCLER" = "1" ]; then
		for file2 in package-configs/$OpenWrt_PATCH_FILE_DIR/*.config; do     echo "# ADD SKB_RECYCLER
CONFIG_KERNEL_SKB_RECYCLER=y
CONFIG_KERNEL_SKB_RECYCLER_MULTI_CPU=y
		" >> "$file2"; done
		echo "----$Matrix_Target----SKB_RECYCLER---"
	fi

	if [ "$ADD_IB" = "1" ]; then
		for file2 in package-configs/$OpenWrt_PATCH_FILE_DIR/*.config; do     echo "# ADD SDK
CONFIG_IB=y
		" >> "$file2"; done
		echo "----$Matrix_Target----IB---"
	fi

	if [ "$TEST_KERNEL" = "1" ]; then
		[ -d $OpenWrt_PATCH_FILE_DIR/core-6-12 ] && cp -r $OpenWrt_PATCH_FILE_DIR/core-6-12/* $OpenWrt_PATCH_FILE_DIR/mypatch-custom-$Matrix_Target
		#rm -rf $OpenWrt_PATCH_FILE_DIR/mypatch-core/0010-mediatek-dts-update-6.12.patch
		rm -rf openwrt/package/kernel/mt76/patches/100-api_compat.patch
		echo "----$Matrix_Target----TEST-KERNEL---"
		sed -i '1i\
CONFIG_TESTING_KERNEL=y\nCONFIG_HAS_TESTING_KERNEL=y' machine-configs/$OpenWrt_PATCH_FILE_DIR/*
		echo "Kernel_Test=_Kernel_Test_Ver" >> $GITHUB_ENV
	fi

	if [ "$Branch" = "24.10-nss-6.12" ]; then
	sed -i '1i\
CONFIG_TESTING_KERNEL=y\nCONFIG_HAS_TESTING_KERNEL=y' machine-configs/$OpenWrt_PATCH_FILE_DIR/*
	echo "----$Matrix_Target--IPQ--TEST-KERNEL---"
	fi

	if [ "$IPQ_Firmware" = "ipq-nss-12-5" ]; then
	sed -i '1i\
CONFIG_NSS_FIRMWARE_VERSION_12_5=y\nCONFIG_NSS_FIRMWARE_VERSION_11_4=n' machine-configs/$OpenWrt_PATCH_FILE_DIR/*
	echo "----$Matrix_Target--IPQ--Firmware-125---"
	sed -i "18i \\\tset wireless.@wifi-iface[0].encryption='psk2'\n\tset wireless.@wifi-iface[0].key='12345678'\n\tset wireless.@wifi-iface[1].encryption='psk2'\n\tset wireless.@wifi-iface[1].key='12345678'" package/kochiya/autoset/files/def_uci/zzz-autoset-ipq
	fi

	if [ "$IPQ_Firmware" = "ipq-nss-12-2" ]; then
	sed -i '1i\
CONFIG_NSS_FIRMWARE_VERSION_12_2=y\nCONFIG_NSS_FIRMWARE_VERSION_11_4=n' machine-configs/$OpenWrt_PATCH_FILE_DIR/*
	echo "----$Matrix_Target--IPQ--Firmware-122---"
	fi

	if [ "$IPQ_Firmware" = "ipq-nss-12-1" ]; then
	sed -i '1i\
CONFIG_NSS_FIRMWARE_VERSION_12_1=y\nCONFIG_NSS_FIRMWARE_VERSION_11_4=n' machine-configs/$OpenWrt_PATCH_FILE_DIR/*
	echo "----$Matrix_Target--IPQ--Firmware-121---"
	fi

	if [ "$IPQ_Firmware" = "ipq-nss-11-4" ]; then
	sed -i '1i\
CONFIG_NSS_FIRMWARE_VERSION_11_4=y' machine-configs/$OpenWrt_PATCH_FILE_DIR/*
	echo "----$Matrix_Target--IPQ--Firmware-114---"
	fi

	if [ "$Branch" = "24.10-nss-dev-618" ]; then
	mkdir -p $OpenWrt_PATCH_FILE_DIR/feeds-routing-patch
	[ -d batman-2410 ] && cp -r batman-2410/* $OpenWrt_PATCH_FILE_DIR/feeds-routing-patch
	echo "----$Matrix_Target----mac80211-6-18---"
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

function add_openwrt_sfe_ipt_k66() {
	if [[ "$Matrix_Target" == *iptables ]]; then
		for file4 in package-configs/$OpenWrt_PATCH_FILE_DIR/*-iptables.config; do     echo "# ADD TURBOACC
CONFIG_PACKAGE_luci-app-turboacc-ipt=y
CONFIG_PACKAGE_luci-app-turboacc-ipt_INCLUDE_PDNSD=n
# CONFIG_PACKAGE_luci-app-fullconenat=y
#offload
CONFIG_PACKAGE_kmod-ipt-offload=y
# sfe
CONFIG_PACKAGE_kmod-fast-classifier=y
CONFIG_PACKAGE_kmod-shortcut-fe=y
CONFIG_PACKAGE_kmod-shortcut-fe-cm=n
" >> "$file4"; done
		echo "----$Matrix_Target-----ipt-sfe---"
		cd openwrt
		wget -N https://raw.githubusercontent.com/chenmozhijin/turboacc/refs/heads/package/pending-6.6/613-netfilter_optional_tcp_window_check.patch -P target/linux/generic/pending-6.6/
		wget -N https://raw.githubusercontent.com/chenmozhijin/turboacc/refs/heads/package/hack-6.6/952-add-net-conntrack-events-support-multiple-registrant.patch -P target/linux/generic/hack-6.6/
		wget -N https://raw.githubusercontent.com/chenmozhijin/turboacc/refs/heads/package/hack-6.6/953-net-patch-linux-kernel-to-support-shortcut-fe.patch -P target/linux/generic/hack-6.6/
		echo "# CONFIG_NF_CONNTRACK_CHAIN_EVENTS is not set" >> "./target/linux/generic/config-6.6"
		echo "# CONFIG_SHORTCUT_FE is not set" >> "./target/linux/generic/config-6.6"
		git clone --depth=1 --single-branch --branch "package" https://github.com/chenmozhijin/turboacc
		mv -n turboacc/shortcut-fe ./package
		sed -i 's/659fa82a431e15af797a6c7069faeee02810453ad8b576c51c29f95a1761a045/0a73db82801fc0406a5bb7ff36e7e1b03f6550797b1aca0e8ea0cec3af465d2b/' \
			./package/shortcut-fe/simulated-driver/Makefile
		rm -rf turboacc
		cd ../
	fi
}

function add_openwrt_sfe_nft_k66() {
	if [[ "$Matrix_Target" == *nftables ]]; then
		for file5 in package-configs/$OpenWrt_PATCH_FILE_DIR/*-nftables.config; do     echo "# ADD TURBOACC
CONFIG_PACKAGE_luci-app-turboacc=y
CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_PDNSD=n
#offload
CONFIG_PACKAGE_kmod-nft-offload=y
# sfe
CONFIG_PACKAGE_kmod-fast-classifier=y
CONFIG_PACKAGE_kmod-shortcut-fe=y
CONFIG_PACKAGE_kmod-shortcut-fe-cm=n
CONFIG_PACKAGE_kmod-nft-fullcone=y
" >> "$file5"; done
		cd openwrt
		curl -sSL https://raw.githubusercontent.com/chenmozhijin/turboacc/luci/add_turboacc.sh -o add_turboacc.sh && bash add_turboacc.sh
		echo "----$Matrix_Target-----NFT-acc----"
		cd ../
	fi
}

function add_openwrt_sfe_kernel_k612() {
	if [ "$TEST_KERNEL" = "1" ]; then
		cd openwrt
		wget -N https://raw.githubusercontent.com/chenmozhijin/turboacc/refs/heads/package/pending-6.12/613-netfilter_optional_tcp_window_check.patch -P target/linux/generic/pending-6.12/
		wget -N https://raw.githubusercontent.com/chenmozhijin/turboacc/refs/heads/package/hack-6.12/952-add-net-conntrack-events-support-multiple-registrant.patch -P target/linux/generic/hack-6.12/
		wget -N https://raw.githubusercontent.com/chenmozhijin/turboacc/refs/heads/package/hack-6.12/953-net-patch-linux-kernel-to-support-shortcut-fe.patch -P target/linux/generic/hack-6.12/
		rm -rf package/turboacc/shortcut-fe/simulated-driver
		cd ../
	fi
	if [ "$Branch" = "24.10-nss-6.12" ]; then
		cd openwrt
		wget -N https://raw.githubusercontent.com/chenmozhijin/turboacc/refs/heads/package/pending-6.12/613-netfilter_optional_tcp_window_check.patch -P target/linux/generic/pending-6.12/
		wget -N https://raw.githubusercontent.com/chenmozhijin/turboacc/refs/heads/package/hack-6.12/952-add-net-conntrack-events-support-multiple-registrant.patch -P target/linux/generic/hack-6.12/
		wget -N https://raw.githubusercontent.com/chenmozhijin/turboacc/refs/heads/package/hack-6.12/953-net-patch-linux-kernel-to-support-shortcut-fe.patch -P target/linux/generic/hack-6.12/
		rm -rf package/turboacc/shortcut-fe/simulated-driver
		rm -rf package/shortcut-fe/simulated-driver
		cd ../
	fi

}

function add_openwrt_sfe_kernel_nss_patch() {
		mkdir -p openwrt/target/linux/qualcommax/patches-6.6
		mkdir -p openwrt/target/linux/qualcommax/patches-6.12
	if [ "$Branch" = "24.10-nss-6.12" ]; then
		cp -f $OpenWrt_PATCH_FILE_DIR/sfe-ipq-6.12/20250425/0600-1-qca-nss-ecm-support-CORE.patch openwrt/target/linux/qualcommax/patches-6.12/0600-1-qca-nss-ecm-support-CORE.patch
		cp -f $OpenWrt_PATCH_FILE_DIR/sfe-ipq-6.12/20250425/0981-0-qca-skbuff-revert.patch openwrt/target/linux/qualcommax/patches-6.12/0981-0-qca-skbuff-revert.patch
	fi

	if [ "$Branch" = "24.10-nss-202502" ] || [ "$Branch" = "24.10-nss-202503" ] || [ "$Branch" = "24.10-nss-202504" ]; then
		cp -f $OpenWrt_PATCH_FILE_DIR/sfe-ipq-6.6/202502/0600-1-qca-nss-ecm-support-CORE.patch openwrt/target/linux/qualcommax/patches-6.6/0600-1-qca-nss-ecm-support-CORE.patch
		cp -f $OpenWrt_PATCH_FILE_DIR/sfe-ipq-6.6/202502/0603-1-qca-nss-clients-add-qdisc-support.patch openwrt/target/linux/qualcommax/patches-6.6/0603-1-qca-nss-clients-add-qdisc-support.patch
	elif [ "$Branch" = "24.10-nss-202601" ] || [ "$Branch" = "24.10-nss-dev" ] || [ "$Branch" = "24.10-nss-dev-nn6000" ]; then
		cp -f $OpenWrt_PATCH_FILE_DIR/sfe-ipq-6.6/202601/0600-1-qca-nss-ecm-support-CORE.patch openwrt/target/linux/qualcommax/patches-6.6/0600-1-qca-nss-ecm-support-CORE.patch
		cp -f $OpenWrt_PATCH_FILE_DIR/sfe-ipq-6.6/202601/0603-1-qca-nss-clients-add-qdisc-support.patch openwrt/target/linux/qualcommax/patches-6.6/0603-1-qca-nss-clients-add-qdisc-support.patch
		cp -f $OpenWrt_PATCH_FILE_DIR/sfe-ipq-6.6/202601/0981-0-qca-skbuff-revert.patch openwrt/target/linux/qualcommax/patches-6.6/0981-0-qca-skbuff-revert.patch
	else
		cp -f $OpenWrt_PATCH_FILE_DIR/sfe-ipq-6.6/20250425/0600-1-qca-nss-ecm-support-CORE.patch openwrt/target/linux/qualcommax/patches-6.6/0600-1-qca-nss-ecm-support-CORE.patch
		cp -f $OpenWrt_PATCH_FILE_DIR/sfe-ipq-6.6/20250425/0603-1-qca-nss-clients-add-qdisc-support.patch openwrt/target/linux/qualcommax/patches-6.6/0603-1-qca-nss-clients-add-qdisc-support.patch
		cp -f $OpenWrt_PATCH_FILE_DIR/sfe-ipq-6.6/20250425/0981-0-qca-skbuff-revert.patch openwrt/target/linux/qualcommax/patches-6.6/0981-0-qca-skbuff-revert.patch
	fi

	if [ "$Branch" = "24.10-nss-dev" ] || [ "$Branch" = "24.10-nss-dev-618" ]; then
		cp -f $OpenWrt_PATCH_FILE_DIR/sfe-ipq-6.6/202603/0600-1-qca-nss-ecm-support-CORE.patch openwrt/target/linux/qualcommax/patches-6.6/0600-1-qca-nss-ecm-support-CORE.patch
	fi
		mkdir -p openwrt/package/qca
		echo "SFE=_SFE" >> $GITHUB_ENV
}
function add_openwrt_nosfe_nss_pkgs() {
		mkdir -p openwrt/package/qca

	if [[ "$Matrix_Target" == *iptables ]]; then
		for file6 in package-configs/$OpenWrt_PATCH_FILE_DIR/*-iptables.config; do     echo "# ADD TURBOACC
CONFIG_PACKAGE_luci-app-turboacc-ipt=y
# CONFIG_PACKAGE_luci-app-turboacc-ipt_INCLUDE_PDNSD is not set
# CONFIG_PACKAGE_luci-app-turboacc-ipt_INCLUDE_SHORTCUT_FE_DRV is not set
" >> "$file6"; done
		sed -i 's/"feeds\/lunatic7\/shortcut-fe"//g' "$DIY_SH"
		echo "----$Matrix_Target-----BBR-acc--nosfe--"
	fi
	if [[ "$Matrix_Target" == *nftables ]]; then
		for file7 in package-configs/$OpenWrt_PATCH_FILE_DIR/*-nftables.config; do     echo "# ADD TURBOACC
CONFIG_PACKAGE_luci-app-turboacc=y
# CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_PDNSD is not set
# CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_SHORTCUT_FE_DRV is not set
" >> "$file7"; done
		sed -i 's/"feeds\/lunatic7\/luci-app-turboacc"//g' "$DIY_SH"
		sed -i 's/"feeds\/lunatic7\/shortcut-fe"//g' "$DIY_SH"
		echo "----$Matrix_Target-----BBR-acc--nosfe--"
	fi

}

function add_openwrt_sfe_patch_fix_66() {

if [ "$SFE_INPUT_STATUS" = "true" ]; then
  local FILE="openwrt/include/kernel-6.6"

  # 取出 LINUX_VERSION-6.6 的小版本
  local LINUX_MINOR
  LINUX_MINOR="$(awk -F'=' '/^LINUX_VERSION-6\.6[[:space:]]*/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$FILE")"
  [[ -z "$LINUX_MINOR" ]] && { echo "未在 ${FILE} 中找到 LINUX_VERSION-6.6，退出。"; exit 1; }

  # 构造当前版本，例如 6.6.129
  local CURRENT_VER
  if [[ "$LINUX_MINOR" == .* ]]; then
    CURRENT_VER="6.6${LINUX_MINOR}"
  else
    CURRENT_VER="6.6.${LINUX_MINOR}"
  fi

  echo "检测到当前内核版本：${CURRENT_VER}（来自 ${FILE}）"

  # 目标版本直接写死在比较里
  local SMALLEST
  SMALLEST="$(printf '%s\n%s\n' "$CURRENT_VER" '6.6.129' | sort -V | head -n 1)"

  if [[ "$SMALLEST" == "$CURRENT_VER" ]] && [[ "$CURRENT_VER" != "6.6.129" ]]; then
    echo "${CURRENT_VER} < 6.6.129，开始下载并覆盖补丁..."
    mkdir -p "openwrt/target/linux/generic/hack-6.6/"
    wget -N "https://raw.githubusercontent.com/chenmozhijin/turboacc/a82479aaebb34c90134d66be2200a9dd50f469fb/hack-6.6/952-add-net-conntrack-events-support-multiple-registrant.patch" \
      -O "openwrt/target/linux/generic/hack-6.6/952-add-net-conntrack-events-support-multiple-registrant.patch"
    echo "完成：openwrt/target/linux/generic/hack-6.6/952-add-net-conntrack-events-support-multiple-registrant.patch"
  else
    echo "${CURRENT_VER} >= 6.6.129，不执行 wget。"
  fi
fi
}

function add_openwrt_sfe_kmods() {
	sed -i 's/kmod-shortcut-fe-cm,kmod-shortcut-fe,kmod-fast-classifier,kmod-fast-classifier-noload,kmod-shortcut-fe-drv,//g' package-configs/kmod_exclude_list*
}

function add_openwrt_files() {
	mkdir -p openwrt/feeds/lunatic7

	mkdir -p openwrt/package/firmware/ipq-wifi/src
	# [ -d $OpenWrt_PATCH_FILE_DIR/bin-files ] && cp -r $OpenWrt_PATCH_FILE_DIR/bin-files/ipq-wifi/src/* openwrt/package/firmware/ipq-wifi/src
	[ -d package ] && cp -r package/* openwrt/package
	[ -d $OpenWrt_PATCH_FILE_DIR/package-for-$OpenWrt_PATCH_FILE_DIR ] && cp -r $OpenWrt_PATCH_FILE_DIR/package-for-$OpenWrt_PATCH_FILE_DIR/* openwrt/package
	[ -d $OpenWrt_PATCH_FILE_DIR/mypatch-core ] && mv -f $OpenWrt_PATCH_FILE_DIR/mypatch-core openwrt/mypatch-core
	[ -d $OpenWrt_PATCH_FILE_DIR/mypatch-custom-$Matrix_Target ] && mv -f $OpenWrt_PATCH_FILE_DIR/mypatch-custom-$Matrix_Target openwrt/mypatch-custom

# for 2410
	if [ "$OpenWrt_PATCH_FILE_DIR" = "openwrt-2410" ]; then
	if [ "$Matrix_Target" == 'ramips-iptables' ] || [ "$Matrix_Target" == 'ramips-nftables' ] || \
		[ "$Matrix_Target" == 'ath79-iptables' ] || [ "$Matrix_Target" == 'ath79-nftables' ]; then
		mkdir -p openwrt/package/kochiya/pcre
		[ -d $OpenWrt_PATCH_FILE_DIR/package-for-2410 ] && cp -r $OpenWrt_PATCH_FILE_DIR/package-for-2410/kochiya/pcre openwrt/package/kochiya/pcre
	else
		[ -d $OpenWrt_PATCH_FILE_DIR/package-for-2410 ] && cp -r $OpenWrt_PATCH_FILE_DIR/package-for-2410/* openwrt/package
	fi
	fi
# for 2410 end

# for 2410 ipq
	if [ "$OpenWrt_PATCH_FILE_DIR" = "openwrt-2410-ipq" ]; then
	[ -d $OpenWrt_PATCH_FILE_DIR/package-for-$OpenWrt_PATCH_FILE_DIR ] && cp -r $OpenWrt_PATCH_FILE_DIR/package-for-$OpenWrt_PATCH_FILE_DIR/* openwrt/package
	fi

	# if [ "$Target_CFG_Machine" = "jdcloud_re-ss-01" ]; then
	# [ -d $OpenWrt_PATCH_FILE_DIR/ipq6000-jd-re-ss-01 ] && cp -r $OpenWrt_PATCH_FILE_DIR/ipq6000-jd-re-ss-01/* openwrt/mypatch-core
	# fi

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

function test_kernel_mediatek_dts_fix() {
	if [ "$TEST_KERNEL" = "1" ]; then
		find openwrt/target/linux/mediatek/dts/ -type f -name 'mt7981*.dts' -exec sed -i 's|#include "mt7981.dtsi"|#include "mt7981b.dtsi"|' {} +
		find openwrt/target/linux/mediatek/dts/ -type f -name 'mt7981*.dtsi' -exec sed -i 's|#include "mt7981.dtsi"|#include "mt7981b.dtsi"|' {} +
	fi
}

function patch_openwrt_core_pre() {
	cd openwrt || return 1
	patch_openwrt_core || return 1
	patch_openwrt_custom || return 1
# for 2410
	if [ "$SFE_INPUT_STATUS" = "true" ] && [ "$TEST_KERNEL" = "1" ]; then
		echo "# CONFIG_NF_CONNTRACK_CHAIN_EVENTS is not set" >> "./target/linux/generic/config-6.12"
		echo "# CONFIG_SHORTCUT_FE is not set" >> "./target/linux/generic/config-6.12"
	fi
# for 2410 ipq
	if [ "$SFE_INPUT_STATUS" = "true" ] && [ "$Branch" = "24.10-nss-6.12" ]; then
		echo "# CONFIG_NF_CONNTRACK_CHAIN_EVENTS is not set" >> "./target/linux/generic/config-6.12"
		echo "# CONFIG_SHORTCUT_FE is not set" >> "./target/linux/generic/config-6.12"
	fi

	cd ../
	test_kernel_mediatek_dts_fix
}

function fix_openwrt_nss_sfe_feeds() {
	if [ "$SFE_INPUT_STATUS" = "true" ]; then
		sed -i '/CONFIG_NF_CONNTRACK_EVENTS=y/ a\
CONFIG_NF_CONNTRACK_CHAIN_EVENTS=y \\' openwrt/feeds/nss_packages/qca-nss-ecm/Makefile
		rm -rf openwrt/feeds/nss_packages/qca-nss-ecm/patches/0006-treewide-rework-notifier-changes-for-5.15.patch
    fi
}

function fix_openwrt_feeds() {
	# [ -e package-configs ] && cp -r package-configs openwrt/package-configs
	[ -d $OpenWrt_PATCH_FILE_DIR/lunatic7-revert ] && mv -f $OpenWrt_PATCH_FILE_DIR/lunatic7-revert openwrt/feeds/lunatic7/lunatic7-revert
	[ -d $OpenWrt_PATCH_FILE_DIR/feeds-luci-patch ] && mv -f $OpenWrt_PATCH_FILE_DIR/feeds-luci-patch openwrt/feeds/luci/feeds-luci-patch
	[ -d $OpenWrt_PATCH_FILE_DIR/feeds-packages-patch ] && mv -f $OpenWrt_PATCH_FILE_DIR/feeds-packages-patch openwrt/feeds/packages/feeds-packages-patch
	[ -d $OpenWrt_PATCH_FILE_DIR/feeds-telephony-patch ] && mv -f $OpenWrt_PATCH_FILE_DIR/feeds-telephony-patch openwrt/feeds/telephony/feeds-telephony-patch
	[ -d $OpenWrt_PATCH_FILE_DIR/feeds-routing-patch ] && mv -f $OpenWrt_PATCH_FILE_DIR/feeds-routing-patch openwrt/feeds/routing/feeds-routing-patch

	cd openwrt
	autosetver
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

function autosetver() {
	if [ "$OpenWrt_PATCH_FILE_DIR" = "openwrt-2410-ipq" ]; then
		case "${Branch:-}" in
			25.12-*) version=25.12-NSS ;;
			*) version=24.10-NSS ;;
		esac
	fi
	if [ "$OpenWrt_PATCH_FILE_DIR" = "openwrt-2410" ]; then
		version=24.10
	fi
	# 在文件的 'exit 0' 之前插入 DISTRIB_DESCRIPTION 信息
	sed -i "/^exit 0$/i\
	\echo \"DISTRIB_DESCRIPTION='OpenWrt $version Compiled by 2U4U'\" >> /etc/openwrt_release
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
		"luci-app-dockerman"
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
		"feeds/luci/applications/luci-app-dockerman"
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

function add_all_ipq_nss_kmod_config() {

if [ "$Branch" = "24.10-nss-6.12" ]; then
KMOD_Compile_Exclude_List_Route=package-configs/kmod_exclude_list_6_12.config
echo "The List exclude route is $KMOD_Compile_Exclude_List_Route"
else
KMOD_Compile_Exclude_List_Route=package-configs/kmod_exclude_list_ipq_nss.config
echo "The List exclude route is $KMOD_Compile_Exclude_List_Route"
fi
all_kmod_config_core
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
elif [ "$TEST_KERNEL" = "1" ]; then
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
	if [ "$OpenWrt_PATCH_FILE_DIR" = "openwrt-2410-ipq" ]; then
	add_all_ipq_nss_kmod_config
	cd openwrt && make defconfig && cd ../
	add_all_ipq_nss_kmod_config
	cd openwrt && make defconfig && cd ../
	add_all_ipq_nss_kmod_config
	cd openwrt && make defconfig && cd ../
	fi

	if [ "$OpenWrt_PATCH_FILE_DIR" = "openwrt-2410" ]; then
	add_all_kmod_config
	cd openwrt && make defconfig && cd ../
	add_all_kmod_config
	cd openwrt && make defconfig && cd ../
	add_all_kmod_config
	cd openwrt && make defconfig && cd ../
	fi

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
		init_gh_env_by_config_set
		;;
	init-gh-env-2410)
		init_gh_env_2410
		config_json_input_set
		patch_json_input_set
		init_gh_env_common
		;;
	init-gh-env-2410-ipq)
		init_gh_env_2410_ipq
		config_json_input_set
		patch_json_input_set
		init_gh_env_common
		;;
	init-openwrt-pkg-config)
		init_openwrt_pkg_config
		;;
	init-openwrt-pkg-config-nss)
		init_openwrt_pkg_config_nss
		;;
	init-openwrt-patch|init-openwrt-patch-2410|init-openwrt-patch-2410-ipq)
		init_openwrt_patch_common
		;;
	ln-openwrt)
		ln_openwrt
		;;
	add-openwrt-sfe-2410)
		add_openwrt_sfe_ipt_k66
		add_openwrt_sfe_nft_k66
		add_openwrt_sfe_kernel_k612
		add_openwrt_sfe_kmods
		;;
	add-openwrt-sfe-2410-ipq)
		add_openwrt_sfe_ipt_k66
		add_openwrt_sfe_nft_k66
		add_openwrt_sfe_kernel_k612
		add_openwrt_sfe_kmods
		# The private OpenWrt 25.12 IPQ branches already carry their
		# qualcommax/NSS kernel patches. Keep the generic turboacc setup,
		# but do not overlay the older 24.10 patch set.
		case "${Branch:-}" in
			25.12-*) ;;
			*) add_openwrt_sfe_kernel_nss_patch ;;
		esac
		;;
	add-openwrt-nosfe-2410-ipq)
		add_openwrt_nosfe_nss_pkgs
		;;
	add-openwrt-files|add-openwrt-files-2410)
		add_openwrt_files
		patch_openwrt_core_pre || exit 1
		add_openwrt_sfe_patch_fix_66 || exit 1
		;;
	add-openwrt-kmods)
		add_openwrt_kmods
		;;
	fix-openwrt-feeds)
		fix_openwrt_nss_sfe_feeds
		fix_openwrt_feeds
		refine_openwrt_config
		;;
	awk-openwrt-config)
		awk_openwrt_config
		;;
	*)
		echo "Usage: $0 {resolve-build-matrix|init-pkg-env|init-gh-env|init-openwrt-patch|add-openwrt-files|add-openwrt-kmods|fix-openwrt-feeds|awk-openwrt-config}" >&2
		exit 1
		;;
esac
