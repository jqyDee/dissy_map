#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/../auction"

cargo zigbuild --release --target aarch64-unknown-linux-musl
BIN=target/aarch64-unknown-linux-musl/release/auction

for i in 1 2 3 4 5; do
  multipass transfer "$BIN" node$i:/home/ubuntu/auction
  multipass exec node$i -- chmod +x /home/ubuntu/auction
done
