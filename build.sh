#!/bin/bash

SECONDS=0
ZIPNAME="Crafters-lisa-$(date '+%Y%m%d-%H%M').zip"

# Export paths and variables
export PATH="$GITHUB_WORKSPACE/kernel_workspace/proton-clang/bin:$PATH"
export STRIP="$GITHUB_WORKSPACE/kernel_workspace/proton-clang/aarch64-linux-gnu/bin/strip"
export KBUILD_COMPILER_STRING=$("$GITHUB_WORKSPACE/kernel_workspace/proton-clang/bin/clang" --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')

export ARCH=arm64
export SUBARCH=arm64
export HEADER_ARCH=arm64
export KBUILD_BUILD_HOST=GitHub@Workflow
export KBUILD_BUILD_USER=nasir

# Clean output folder if specified
if [[ $1 = "-c" || $1 = "--clean" ]]; then
    rm -rf out
    echo "Cleaned output folder"
fi

mkdir -p out

# Merge configuration files
ARCH=arm64 scripts/kconfig/merge_config.sh -O out arch/arm64/configs/vendor/lahaina-qgki_defconfig \
                                           arch/arm64/configs/vendor/xiaomi_QGKI.config \
                                           arch/arm64/configs/vendor/debugfs.config || {
    echo "Configuration merge failed."
    exit 1
}

echo -e "\nStarting compilation...\n"

MAKE_PARAMS="O=out ARCH=arm64 AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump \
             CC=clang STRIP=llvm-strip CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi-"

make -j$(nproc --all) $MAKE_PARAMS || {
    echo "Kernel compilation failed."
    exit 1
}

make -j$(nproc --all) $MAKE_PARAMS INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 modules_install || {
    echo "Module installation failed."
    exit 1
}

# Define paths for kernel, dtb, and dtbo
kernel="out/arch/arm64/boot/Image"
dtb="out/arch/arm64/boot/dts/vendor/qcom/yupik.dtb"
dtbo="out/arch/arm64/boot/dts/vendor/qcom/lisa-sm7325-overlay.dtbo"

if [[ ! -f "$kernel" || ! -f "$dtb" || ! -f "$dtbo" ]]; then
    echo -e "\nCompilation failed: Missing kernel, DTB, or DTBO."
    exit 1
fi

echo -e "\nKernel compiled successfully! Zipping up...\n"

# Clone AnyKernel3 and copy files
git clone -q https://github.com/ItsVixano/AnyKernel3 -b lisa-aosp || {
    echo "Failed to clone AnyKernel3 repository."
    exit 1
}

cp "$kernel" AnyKernel3
cp "$dtb" AnyKernel3/dtb

# Create DTBO image
python3 scripts/dtc/libfdt/mkdtboimg.py create AnyKernel3/dtbo.img --page_size=4096 "$dtbo" || {
    echo "Failed to create DTBO image."
    exit 1
}

# Copy kernel modules
mkdir -p AnyKernel3/modules/vendor/lib/modules
find out/modules/lib/modules/5.4* -name '*.ko' -exec cp {} AnyKernel3/modules/vendor/lib/modules/ \;

cp out/modules/lib/modules/5.4*/modules.{alias,dep,softdep} AnyKernel3/modules/vendor/lib/modules/
cp out/modules/lib/modules/5.4*/modules.order AnyKernel3/modules/vendor/lib/modules/modules.load

# Fix modules dependencies
sed -i 's|\(kernel/[^: ]*/\)\([^: ]*\.ko\)|/vendor/lib/modules/\2|g' AnyKernel3/modules/vendor/lib/modules/modules.dep
sed -i 's|.*\/||g' AnyKernel3/modules/vendor/lib/modules/modules.load

# Clean build artifacts
rm -rf out/arch/arm64/boot out/modules

# Create the flashable ZIP
cd AnyKernel3 || exit 1
zip -r9 "../$ZIPNAME" * -x .git README.md *placeholder || {
    echo "Failed to create the ZIP file."
    exit 1
}
cd ..

# Clean up AnyKernel3 directory
rm -rf AnyKernel3

echo -e "\nBuild and packaging completed successfully in $SECONDS seconds!"
