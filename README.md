# vk
A console client for vk.com written in Nim

# Navigation

+ arrow keys
+ w, a, s, d
+ h, j, k, l
+ enter

# Workflow
[![demo](https://asciinema.org/a/47nt6rjyyxuwel9y5gtv8xs4h.png)](https://asciinema.org/a/47nt6rjyyxuwel9y5gtv8xs4h?autoplay=1)

# Dependencies

nimble install ncurses

# Compilation

nim c -d:ssl --threads:on -r --verbosity:0 -d:debug --gc:boehm --threadAnalysis:off main.nim


