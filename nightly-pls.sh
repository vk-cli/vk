#!/bin/bash

echo "installing rustup"
sudo echo ""
yes | sudo pacman -S --confirm rustup

echo "installing nightly toolchain"
rustup toolchain install nightly
rustup default nightly

printf "top top top\nuse cargo run\n"
