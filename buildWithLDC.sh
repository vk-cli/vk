#!/bin/bash

export DFLAGS="-disable-linker-strip-dead $@"
dub build --force --compiler=ldc

