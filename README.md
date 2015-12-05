# vk
A console client for vk.com written in Nim

# Navigation

+ arrow keys
+ w, a, s, d
+ h, j, k, l
+ enter

# Workflow
[![demo](https://asciinema.org/a/9xk3udeee2xf7m31ngpwxzc57.png)](https://asciinema.org/a/9xk3udeee2xf7m31ngpwxzc57?autoplay=1)

# Compilation

debug:
>nim c -d:ssl --threads:on -r --verbosity:0 -d:debug --gc:boehm --threadAnalysis:off main.nim


