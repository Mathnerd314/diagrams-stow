This repository has several files which I find useful for developing
on [diagrams](http://github.com/diagrams/).  I check out this repo as
the directory where I keep the diagrams code.

# mr

Running `mr update` will checkout all the repositories, `mr run git checkout
master` will switch to the master branch, and so forth.

# packdeps

[packdeps](http://hackage.haskell.org/package/packdeps) is a helpful
script that checks that upper bounds in a cabal file do not prevent
using the latest released version.  The shell script here runs
packdeps on most of the Diagrams packages.

# Nix

I run `cabal2nix.sh` to generate the default.nix files, and then
`nix-shell` to enter a subshell with all necessary Haskell packages installed.
