# vk
A console (ncurses) client for vk.com written in D


### Unstable branch
+ **master** - current upstream 

### Stable Version
+ **0.7.1a** - [latest release](https://vk.com/wall-69278962_1157)

# Screenshots

![alt tag](http://cs630123.vk.me/v630123942/25fc7/YOqfnerj4bE.jpg)
![alt tag](http://cs630123.vk.me/v630123942/25fd7/hcgITGtqEd0.jpg)

# Install

## ArchLinux

```
yaourt -S vk-cli
vk
```

## MacOS

```
brew install dub dmd curl openssl mplayer
brew install homebrew/dupes/ncurses
brew doctor
brew link ncurses —force
brew install libxslt xmlto
export XML_CATALOG_FILES="/usr/local/etc/xml/catalog"
git clone git://anongit.freedesktop.org/xdg/xdg-utils
cd xdg-utils
./configure —prefix=/usr/local
make
make install
```

then `Build`

## Build

```
git clone https://github.com/HaCk3Dq/vk
cd vk
git checkout 0.7.1a
dub
```
builds `vk` binary for your platform.

## Dependencies

+ ncurses >= 5.7
+ curl
+ openssl

Make dependencies:

+ dub 
+ dmd >= 2.071

Optional:

+ mpv >= 0.9.0: for music playback

### EXCLUSIVE UBUNTU DEPENDENCIES

+ libncursesw5-dev
+ libssl-dev
+ mplayer
+ curl

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

