# vk
A console (ncurses) client for vk.com written in D

# Screenshots

![alt tag](http://cs630123.vk.me/v630123942/25fc7/YOqfnerj4bE.jpg)
![alt tag](http://cs630123.vk.me/v630123942/25fd7/hcgITGtqEd0.jpg)

# Donate
If you want to support us, here you are - https://money.yandex.ru/to/410014355699643

# Install

## ArchLinux

```sh
yaourt -S vk-cli # or vk-cli-git
vk
```

## Ubuntu 

```
sudo apt-add-repository ppa:mc3man/mpv-tests
sudo apt-get update
sudo apt-get install libncursesw5-dev libssl-dev curl mpv
```

then `Build` 

OR

install deb package from releases page `sudo dpkg -i vk-cli.deb` 

## MacOS

```
brew install dub dmd curl openssl mpv
brew install homebrew/dupes/ncurses
brew doctor
brew link ncurses -force
```

then `Build`

## Build

```
git clone https://github.com/vk-cli/vk
cd vk
git checkout VER
dub build
```
(where `VER` is version number)
builds `vk` binary for your platform.
You can find number of latest version here: https://github.com/vk-cli/vk/releases
## Dependencies

+ ncurses >= 5.7
+ curl
+ openssl

Make dependencies:

+ dub 
+ dmd >= 2.071

Optional:

+ mpv >= 0.22.0: for music playback

### Our GPG keys

To verify signed files, first you need to import keys:

` $ gpg  --keyserver pgp.mit.edu --recv-keys 0x3457ECED `

Now you can verify files and install signed packages:

` $ gpg --verify signed-file.sig signed-file `

`gpg: Good signature from "vk-cli developers team <vk-cli.dev@ya.ru>"`

This output indicates that file is properly signed and isn't damaged

