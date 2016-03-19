# vk
A console (ncurses) client for vk.com written in D

### Branches
+ **master** - current upstream (may be unstable) 

# Install

## Build

```
git clone https://github.com/HaCk3Dq/vk
cd vk
```
If you want build one of specific versions instead of master upstream (alpha-1, for example), you need to run
```
git checkout ver
```
where is `ver` - name of branch that you want to build

```
dub build
```
builds `vk` binary for your platform

## Dependencies

+ ncurses >= 5.7

Optional:

+ mplayer: for music playback
+ xclip: paste from X clipboard in chats (currently not implemented)

For build:

+ dub
+ dmd

# How to use

## Navigation

+ Arrow Keys
+ W, A, S, D
+ H, J, K, L
+ Enter
+ PageUp - scroll half screen up
+ PageDown - scroll half screen down
+ Home - first entry 
+ End - last entry
+ Q - to exit
