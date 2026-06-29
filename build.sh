#!/bin/bash
set -e

# ---- repo tool (Ubuntu runner đôi khi thiếu) ----
if ! command -v repo >/dev/null; then
  mkdir -p ~/.bin
  curl -s https://storage.googleapis.com/git-repo-downloads/repo > ~/.bin/repo
  chmod a+rx ~/.bin/repo
  export PATH=~/.bin:$PATH
fi

git config --global user.email "ci@local"
git config --global user.name "ci"
git config --global color.ui false

# ---- sync source ----
mkdir kernel && cd kernel
repo init -u https://android.googlesource.com/kernel/manifest \
  -b android-msm-sunfish-4.14-android13-qpr3 --depth=1
repo sync -j"$(nproc)" --no-tags --force-sync

cd private/msm-google

# ---- nhúng SukiSU-Ultra (susfs tích hợp sẵn, manual hook cho non-GKI) ----
curl -LSs "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/main/kernel/setup.sh" | bash -s susfs-main

# ---- config ----
CFG=arch/arm64/configs/sunfish_defconfig

# tắt kprobe (non-GKI dùng manual hook)
sed -i 's/^CONFIG_KPROBES=y/# CONFIG_KPROBES is not set/' "$CFG" || true

# tắt CFI + Shadow Call Stack phòng hờ
sed -i 's/^CONFIG_CFI_CLANG=y/# CONFIG_CFI_CLANG is not set/' "$CFG" || true
sed -i 's/^CONFIG_SHADOW_CALL_STACK=y/# CONFIG_SHADOW_CALL_STACK is not set/' "$CFG" || true

# tắt LTO trong defconfig (nếu không, link vmlinux sẽ OOM trên runner)
sed -i '/^CONFIG_LTO_CLANG=y/d' "$CFG" || true
sed -i '/^CONFIG_THINLTO=y/d' "$CFG" || true
sed -i '/^CONFIG_LTO_CLANG_THIN=y/d' "$CFG" || true
echo "CONFIG_LTO_NONE=y" >> "$CFG"

# config KSU + SukiSU
cat >> "$CFG" <<'EOF'
CONFIG_KSU=y
CONFIG_KSU_MANUAL_HOOK=y
CONFIG_KPM=y
CONFIG_KALLSYMS=y
CONFIG_KALLSYMS_ALL=y
EOF

# tắt check_defconfig (tránh savedefconfig mismatch)
echo 'POST_DEFCONFIG_CMDS=""' >> build.config.sunfish

# ---- build ----
cd "$GITHUB_WORKSPACE/kernel"
LTO=none BUILD_CONFIG=private/msm-google/build.config.sunfish build/build.sh

# ---- gom output ----
mkdir -p "$GITHUB_WORKSPACE/out"
cp out/android-msm-pixel-4.14/dist/Image.lz4-dtb "$GITHUB_WORKSPACE/out/"
cp out/android-msm-pixel-4.14/dist/dtbo.img "$GITHUB_WORKSPACE/out/" || true
echo "=== BUILD DONE ==="
ls -lh "$GITHUB_WORKSPACE/out/"
