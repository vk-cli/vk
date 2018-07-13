# vk
A console (ncurses) client for vk.com written in D

# Project is abandoned

vk-cli is mostly abandoned due to lack of time, very poor state of codebase (which definitely needs to be rewritten from scratch) and mainly - due to vk politics which becomes worse from day to day, starting from music, online and ending with advertisements in newsfeed. So we (devs) won't continue to support this project.

If you're looking for a way to not use actual vk.com but want to save ability to get content from there, there's some projects from us such as [vktotg](https://github.com/HaCk3Dq/vktotg) tool which helps to reupload music from your page to private channel in telegram, and planned news aggregator, which will anonymously (without your access_token) gather news from public pages you interested in, and forward it to the destination you prefer (telegram bot, e-mail, etc)

But if you just want CLI client for vk - we can't help with it anymore :)

# Screenshots

![alt tag](http://cs630123.vk.me/v630123942/25fc7/YOqfnerj4bE.jpg)
![alt tag](http://cs630123.vk.me/v630123942/25fd7/hcgITGtqEd0.jpg)

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

## Gentoo

```sh
layman -fa glicOne
sudo emerge net-im/vk # for vk-9999 you need install dub, dmd and dlang-tools from dlang overlay
vk-cli
```
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
(where `VER` is the version number)

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

