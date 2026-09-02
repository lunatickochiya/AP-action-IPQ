#!/bin/bash
#=================================================
# this script is from https://github.com/lunatickochiya/Lunatic-s805-rockchip-Action
# Written By lunatickochiya
# QQ group :286754582  https://jq.qq.com/?_wv=1027&k=5QgVYsC
#=================================================


function autosetver() {
    version=24.10-NSS

    # 在文件的 'exit 0' 之前插入 DISTRIB_DESCRIPTION 信息
    sed -i "/^exit 0$/i\
    \echo \"DISTRIB_DESCRIPTION='OpenWrt $version Compiled by 2U4U'\" >> /etc/openwrt_release
    " package/kochiya/autoset/files/def_uci/zzz-autoset*

    # 使用通配符匹配所有以 zzz-autoset- 开头的文件并执行 grep
    for file in package/kochiya/autoset/files/def_uci/zzz-autoset-*; do
        grep DISTRIB_DESCRIPTION "$file"
    done
}


function set_firewall_allow() {
sed -i '/^	commit$/i\
	set firewall.@zone[1].input="ACCEPT"
' package/kochiya/autoset/files/def_uci/zzz-autoset*
}

function remove_error_package() {

packages=(
    "luci-app-dockerman"
    "luci-app-smartdns"
    "rtl8821cu"
    "xray-core"
    "smartdns"
)

for package in "${packages[@]}"; do
        echo "卸载软件包 $package ..."
        ./scripts/feeds uninstall $package
        echo "软件包 $package 已卸载。"
done

directories=(
    "feeds/luci/applications/luci-app-dockerman"
    "feeds/luci/applications/luci-app-smartdns"
    "feeds/lunatic7/rtl8821cu"
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
rm -rf tmp
./scripts/feeds update -i
./scripts/feeds install -a -d y
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

function patch_openwrt_core() {
        for i in $( ls mypatch-core ); do
            echo Applying mypatch-core $i
            patch -p1 --no-backup-if-mismatch --quiet < mypatch-core/$i
        done
        }

function patch_openwrt_custom() {
        for i in $( ls mypatch-custom ); do
            echo Applying mypatch-custom $i
            patch -p1 --no-backup-if-mismatch --quiet < mypatch-custom/$i
        done
        }

function patch_package() {
        for packagepatch in $( ls feeds/packages/feeds-packages-patch ); do
            cd feeds/packages/
            echo Applying feeds-packages-patch $packagepatch
            patch -p1 --no-backup-if-mismatch < feeds-packages-patch/$packagepatch
            cd ../..
        done
        }

function patch_luci() {
        for lucipatch in $( ls feeds/luci/feeds-luci-patch ); do
            cd feeds/luci/
            echo Applying feeds-luci-patch $lucipatch
            patch -p1 --no-backup-if-mismatch < feeds-luci-patch/$lucipatch
            cd ../..
        done
        }

function patch_feeds_telephony() {
        for telepatch in $( ls feeds/telephony/feeds-telephony-patch ); do
        cd feeds/telephony/
        echo Applying feeds-telephony-patch $telepatch
            patch -p1 --no-backup-if-mismatch < feeds-telephony-patch/$telepatch
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

function patch_kernel61() {

for rockpatch in $( ls tpm312/openwrt-24.10-k6.1/core ); do
    echo Applying openwrt-24.10-k6.1 $rockpatch
    patch -p1 --no-backup-if-mismatch --quiet < tpm312/openwrt-24.10-k6.1/core/$rockpatch
done

directories2=(
    "package/kernel/mac80211"
    "package/kernel/mt76"
)

for directory2 in "${directories2[@]}"; do
    if [ -d "$directory2" ]; then
        echo "目录 $directory2 存在，进行删除操作..."
        rm -r "$directory2"
        echo "目录 $directory2 已删除。"
    else
        echo "目录 $directory2 不存在。"
    fi
done

source_directory="tpm312/package/kernel/mac80211"
source_directory2="tpm312/package/kernel/mt76"
target_directory="package/kernel/mac80211"
target_directory2="package/kernel/mt76"

# 检查源目录1是否存在
if [ -d "$source_directory" ]; then
    echo "源目录 $source_directory 存在。"

    # 检查目标目录1是否存在
    if [ -d "$target_directory" ]; then
        echo "目标目录 $target_directory 已经存在，无需移动。"
    else
        echo "目标目录 $target_directory 不存在，进行恢复操作..."
        mv -f "$source_directory" "$target_directory"
        echo "目录 $source_directory 已移动到目标目录 $target_directory。"
    fi
else
    echo "源目录 $source_directory 不存在。"
fi

# 检查源目录2是否存在
if [ -d "$source_directory2" ]; then
    echo "源目录 $source_directory2 存在。"

    # 检查目标目录2是否存在
    if [ -d "$target_directory2" ]; then
        echo "目标目录 $target_directory2 已经存在，无需移动。"
    else
        echo "目标目录 $target_directory2 不存在，进行恢复操作..."
        mv -f "$source_directory2" "$target_directory2"
        echo "目录 $source_directory2 已移动到目标目录 $target_directory2。"
    fi
else
    echo "源目录 $source_directory2 不存在。"
fi

rm -rf tpm312
}

function remove_firewall() {

directories1=(
    "package/network/config/firewall"
    "package/network/config/firewall4"
)

for directory1 in "${directories1[@]}"; do
    if [ -d "$directory1" ]; then
        echo "目录 $directory1 存在，进行删除操作..."
        rm -r "$directory1"
        echo "目录 $directory1 已删除。"
    else
        echo "目录 $directory1 不存在。"
    fi
done
        }

# add luci

function add_ipq_iptables_packages() {
echo "$(cat package-configs/ipq-common-iptables.config)" >> package-configs/.config
mv -f package-configs/.config .config
}

function add_ipq_nftables_packages() {
echo "$(cat package-configs/ipq-common-nftables.config)" >> package-configs/.config
mv -f package-configs/.config .config
}

function add_ath79_iptables_packages() {
echo "$(cat package-configs/ath79-common-iptables.config)" >> package-configs/.config
mv -f package-configs/.config .config
}

function add_ath79_nftables_packages() {
echo "$(cat package-configs/ath79-common-nftables.config)" >> package-configs/.config
mv -f package-configs/.config .config
}

function add_ramips_iptables_packages() {
echo "$(cat package-configs/ramips-common-iptables.config)" >> package-configs/.config
mv -f package-configs/.config .config
}

function add_ramips_nftables_packages() {
echo "$(cat package-configs/ramips-common-nftables.config)" >> package-configs/.config
mv -f package-configs/.config .config
}

function add_mt798x_iptables_packages() {
echo "$(cat package-configs/mt798x-common-iptables.config)" >> package-configs/.config
mv -f package-configs/.config .config
}

function add_mt798x_nftables_packages() {
echo "$(cat package-configs/mt798x-common-nftables.config)" >> package-configs/.config
mv -f package-configs/.config .config
}

function add_mt798x_nousb_nftables_packages() {
echo "$(cat package-configs/mt798x-nousb-nftables.config)" >> package-configs/.config
mv -f package-configs/.config .config
}

function add_mt798x_nousb_iptables_packages() {
echo "$(cat package-configs/mt798x-nousb-iptables.config)" >> package-configs/.config
mv -f package-configs/.config .config
}

function add_mt798x_packages() {
echo "$(cat package-configs/mt798x-common.config)" >> package-configs/.config
mv -f package-configs/.config .config
}

function add_mt798x_istore_packages() {
echo "$(cat package-configs/mt798x-common-istore.config)" >> package-configs/.config
mv -f package-configs/.config .config
}

function add_test_kernel_config() {
sed -i '1i\
CONFIG_TESTING_KERNEL=y\nCONFIG_HAS_TESTING_KERNEL=y\nCONFIG_LINUX_6_1=y' machine-configs/single/*
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

if [ "$1" == "mt798x-iptables" ]; then
autosetver
remove_error_package_not_install
patch_package
patch_luci
patch_lunatic7
add_mt798x_iptables_packages
elif [ "$1" == "mt798x-nftables" ]; then
autosetver
remove_error_package_not_install
patch_package
patch_luci
patch_lunatic7
add_mt798x_nftables_packages
elif [ "$1" == "mt798x-nousb-nftables" ]; then
autosetver
remove_error_package_not_install
patch_package
patch_luci
patch_lunatic7
add_mt798x_nousb_nftables_packages
elif [ "$1" == "mt798x-nousb-iptables" ]; then
autosetver
remove_error_package_not_install
patch_package
patch_luci
patch_lunatic7
add_mt798x_nousb_iptables_packages
elif [ "$1" == "mt798x-istore" ]; then
autosetver
remove_error_package_not_install
patch_package
patch_luci
patch_lunatic7
add_mt798x_istore_packages
elif [ "$1" == "ramips-iptables" ]; then
autosetver
remove_error_package_not_install
patch_package
patch_luci
patch_lunatic7
add_ramips_iptables_packages
elif [ "$1" == "ramips-nftables" ]; then
autosetver
remove_error_package_not_install
patch_package
patch_luci
patch_lunatic7
add_ramips_nftables_packages
elif [ "$1" == "ath79-iptables" ]; then
autosetver
remove_error_package_not_install
patch_package
patch_luci
patch_lunatic7
add_ath79_iptables_packages
elif [ "$1" == "ath79-nftables" ]; then
autosetver
remove_error_package_not_install
patch_package
patch_luci
patch_lunatic7
add_ath79_nftables_packages
elif [ "$1" == "ipq-iptables" ]; then
autosetver
remove_error_package_not_install
patch_package
patch_luci
patch_lunatic7
patch_feeds_telephony
add_ipq_iptables_packages
change_qca_start_order
elif [ "$1" == "ipq-nftables" ]; then
autosetver
remove_error_package_not_install
patch_package
patch_luci
patch_lunatic7
patch_feeds_telephony
add_ipq_nftables_packages
change_qca_start_order
elif [ "$1" == "patch-openwrt" ]; then
patch_openwrt_core
patch_openwrt_custom
elif [ "$1" == "firewallremove" ]; then
remove_firewall
elif [ "$1" == "firewall-allow-wan" ]; then
set_firewall_allow
elif [ "$1" == "setver" ]; then
autosetver
elif [ "$1" == "kernel61" ]; then
patch_kernel61
elif [ "$1" == "patchtele" ]; then
patch_op_tele
elif [ "$1" == "add-test-config" ]; then
add_test_kernel_config
else
echo "Invalid argument"
fi
