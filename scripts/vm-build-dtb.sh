#!/bin/sh
# Compile only the cepheus DTB from the kernel tree (VM on macOS, host on Linux; seconds, no kernel build).
# Output: <handoff>/images/test.dtb
. "$(dirname "$0")/common.sh"
mkdir -p "$HANDOFF_DIR/images"
vmsh 'cd ~/src/linux-v7.0.0-sm8150 && make -s ARCH=arm64 LLVM=1 qcom/sm8150-xiaomi-cepheus.dtb 2>&1 | grep -v NT36672_SPI; cp arch/arm64/boot/dts/qcom/sm8150-xiaomi-cepheus.dtb "'"$HANDOFF_DIR"'/images/test.dtb"' \
  && ls -la "$HANDOFF_DIR/images/test.dtb"
