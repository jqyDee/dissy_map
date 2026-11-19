#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/../auction"

# Build for the VMs' architecture (multipass VMs match the host CPU:
# aarch64 on Apple Silicon, x86_64 on Intel/AMD). Ask a VM directly.
arch=$(multipass exec node1 -- uname -m </dev/null)

case "$arch" in
  aarch64|arm64) TARGET=aarch64-unknown-linux-musl ;;
  x86_64|amd64)  TARGET=x86_64-unknown-linux-musl ;;
  *) echo "unsupported VM architecture: $arch" >&2; exit 1 ;;
esac

echo "building for $TARGET"
rustup target add "$TARGET" >/dev/null 2>&1 || true
cargo zigbuild --release --target "$TARGET"
BIN=target/$TARGET/release/auction

for i in 1 2 3 4 5; do
  multipass transfer "$BIN" node$i:/home/ubuntu/auction
  multipass exec node$i -- chmod +x /home/ubuntu/auction
done
