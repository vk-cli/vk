# vk
A console (ncurses) client for vk.com written in D



### Our GPG keys

```
C990 689C 7692 B5E0 2057  6092 67DB 7D5C 3457 ECED 
vk-cli developers team <vk-cli.dev@ya.ru>
https://pgp.mit.edu/
```

To verify signed files, first you need to import keys:

` $ gpg  --keyserver pgp.mit.edu --recv-keys 0x3457ECED `

Now you can verify files and install signed packages:

` $ gpg --verify signed-file.sig signed-file `

`gpg: Good signature from "vk-cli developers team <vk-cli.dev@ya.ru>"`

This output indicates that file is properly signed and isn't damaged

### Branches
+ **master** - current upstream (may be unstable) 

### Tags
+ **0.7a1** - first alpha release (https://vk.com/wall-69278962_1081)

# Install

## Build

```
git clone https://github.com/HaCk3Dq/vk
git checkout 0.7a1
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

Make dependencies

+ dub 
+ dmd >= 2.071

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
