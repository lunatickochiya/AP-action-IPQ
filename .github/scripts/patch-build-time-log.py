#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 RK-action
#
# 给 OpenWrt 树注入 BUILD_TIME_LOG 统计（包 prepare/configure/compile/install），
# 并把 build-time-log.sh / build-time-report.pl 放进 scripts/。
#
# 用法：patch-build-time-log.py <openwrt 树> [--scripts-dir .github/scripts]
#
# 只改 rules.mk 和 include/package.mk；不动 host/kernel 构建，避免影响工具链。

import argparse
import os
import shutil
import sys

BLOCK = """# Set BUILD_TIME_LOG=<file> in the environment to record a begin and an end
# event for every prepare, configure, compile and install stage. Turn the log
# into a report with scripts/build-time-report.pl.
ifneq ($(BUILD_TIME_LOG),)
  BUILD_TIME_LOG_FILE:=$(if $(filter /%,$(BUILD_TIME_LOG)),$(BUILD_TIME_LOG),$(TOPDIR)/$(BUILD_TIME_LOG))
  BuildTimeLog = @$(SCRIPT_DIR)/build-time-log.sh $(BUILD_TIME_LOG_FILE) $(1) $(2) "$(if $(BUILD_SUBDIR),$(BUILD_SUBDIR),$(CURDIR))$(if $(BUILD_VARIANT),/$(BUILD_VARIANT))"
else
  BuildTimeLog =
endif
"""


def die(msg):
    print("::error ::patch-build-time-log: " + msg, file=sys.stderr)
    sys.exit(1)


def insert_after(lines, needle, newline, start=0):
    for i in range(start, len(lines)):
        if lines[i].strip().startswith(needle):
            lines.insert(i + 1, newline)
            return i + 1
    die("anchor not found: " + needle)


def insert_before(lines, needle, newline, start=0):
    for i in range(start, len(lines)):
        if lines[i].strip() == needle:
            lines.insert(i, newline)
            return i
    die("anchor not found: " + needle)


def patch_rules(tree):
    path = os.path.join(tree, "rules.mk")
    text = open(path, encoding="utf-8").read()
    if "BuildTimeLog" in text:
        print("rules.mk already patched")
        return
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.strip().startswith("PKG_INFO_DIR"):
            lines[i:i] = BLOCK.rstrip("\n").splitlines() + [""]
            break
    else:
        die("PKG_INFO_DIR not found in rules.mk")
    open(path, "w", encoding="utf-8").write("\n".join(lines).rstrip("\n") + "\n")
    print("patched rules.mk")


def patch_package_mk(tree):
    path = os.path.join(tree, "include/package.mk")
    text = open(path, encoding="utf-8").read()
    if "BuildTimeLog" in text:
        print("include/package.mk already patched")
        return
    lines = text.splitlines()

    stages = [
        ("$(STAMP_PREPARED): $(STAMP_PREPARED_DEPENDS)", "prepare",
         "$(foreach hook,$(Hooks/Prepare/Post)"),
        ("$(STAMP_CONFIGURED): $(STAMP_PREPARED) $(STAMP_CONFIGURED_DEPENDS)", "configure",
         "$(foreach hook,$(Hooks/Configure/Post)"),
        ("$(STAMP_BUILT): $(STAMP_CONFIGURED) $(STAMP_BUILT_DEPENDS)", "compile",
         "$(foreach hook,$(Hooks/Install/Post)"),
        ("$(STAMP_INSTALLED): $(STAMP_BUILT)", "install",
         "rm -rf $(TMP_DIR)/stage-$(PKG_DIR_NAME)"),
    ]

    for target, stage, anchor in stages:
        begin_at = insert_after(lines, target, "\t$(call BuildTimeLog,begin,%s)" % stage)
        # The end marker goes just before the `touch $$@` that closes this target.
        anchor_at = None
        for i in range(begin_at, len(lines)):
            if anchor in lines[i]:
                anchor_at = i
                break
        if anchor_at is None:
            die("stage anchor not found: %s (%s)" % (anchor, stage))
        insert_before(lines, "touch $$@", "\t$(call BuildTimeLog,end,%s)" % stage, anchor_at)

    open(path, "w", encoding="utf-8").write("\n".join(lines).rstrip("\n") + "\n")
    print("patched include/package.mk")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tree")
    ap.add_argument("--scripts-dir", default=".github/scripts")
    args = ap.parse_args()

    if not os.path.isfile(os.path.join(args.tree, "rules.mk")):
        die("not an OpenWrt tree: " + args.tree)

    for name in ("build-time-log.sh", "build-time-report.pl"):
        src = os.path.join(args.scripts_dir, name)
        if not os.path.isfile(src):
            die("missing " + src)
        dst = os.path.join(args.tree, "scripts", name)
        shutil.copyfile(src, dst)
        os.chmod(dst, 0o755)
        print("installed scripts/" + name)

    patch_rules(args.tree)
    patch_package_mk(args.tree)


if __name__ == "__main__":
    main()
