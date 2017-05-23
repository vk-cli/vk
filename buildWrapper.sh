#!/bin/bash

# buidWrapper [ver] [64/32]

TARCH="$2"
NAME="vk-$1-$TARCH"
NAMEBIN="$NAME-bin"
NAMEPACK="$NAMEBIN.7z"

rm vk
./buildRelease.sh static "$TARCH"
if [[ "$?" -eq "0" ]]; then
  mv vk "$NAMEBIN"
  7z a "$NAMEPACK" "$NAMEBIN"
  rm "$NAMEBIN"
fi
