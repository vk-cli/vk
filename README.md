# vk
A console (ncurses) client for vk.com written in D

### Branches
+ **master** - current upstream (may be unstable) 

# Install

## Build

```
git clone https://github.com/HaCk3Dq/vk
cd vk
dub
```
builds `vk` binary for your platform.

If you want build one of specific versions instead of master upstream (alpha-1, for example), you need to run
```
git checkout ver
```
where `ver` - is the name of the branch that you want to build

## Dependencies

+ ncurses >= 5.7
+ curl
+ openssl
+ dub
+ dmd

Optional:

+ mplayer: for music playback

# How to use

+ Arrow Keys
+ W, A, S, D
+ H, J, K, L
+ Enter
+ PageUp - scroll half screen up
+ PageDown - scroll half screen down
+ Home - first entry 
+ End - last entry
+ Q - to exit
+ R - force refresh current window
