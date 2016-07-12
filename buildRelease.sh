#!/bin/bash

dubarch="x86_64"
dubtype="release"
dubconf=""

if [[ "$2" == '32' ]]; then
  dubarch="x86"
fi

if [[ "$1" == 'shared' ]]; then
  dubconf="release-shared"
elif [[ "$1" == 'static' ]]; then
  dubconf="release-static"
elif [[ "$1" == 'debug' ]]; then
  dubconf="debug"
  dubtype="debug"
fi

dubtype="debug" # for remove optimizations

echo "Building with:"
echo "config: $dubconf"
echo "build: $dubtype"
echo "arch: $dubarch"
echo ""
dub build --config=$dubconf --build=$dubtype --arch=$dubarch --force
