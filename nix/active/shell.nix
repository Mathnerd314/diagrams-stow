{ pkgs ? import <nixpkgs> {}, haskellPackages ? pkgs.haskellPackages }:

let 
  hs = haskellPackages.override {
        extension = self: super: rec {
          hsPkg = pkg: version: self.callPackage "/home/bergey/code/nixHaskellVersioned/${pkg}/${version}.nix" {};
          # lens = hsPkg "lens" "4.6";
          linear = hsPkg "linear" "1.15.2";
          thisPackage = self.callPackage ./. {};
      };
    };
  in
      pkgs.lib.overrideDerivation hs.thisPackage (attrs: {
       buildInputs = [hs.cabalInstall ] ++ attrs.buildInputs;
 })
