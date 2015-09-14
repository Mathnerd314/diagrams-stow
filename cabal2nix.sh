export olddir=$PWD
cabal sandbox init
for pkg in $(sed -n 's/\[\(.*\)\]/\1/p' .mrconfig); do
    cd $olddir/$pkg
    cabal2nix ./. > default.nix
    cabal sandbox init --sandbox=$olddir/.cabal-sandbox
done
cd $olddir
