{ pkgs ? import <nixpkgs> {}, haskellPackages ? pkgs.haskellPackages }:

let 
  hs = haskellPackages.override {
        extension = self: super: rec {
        hsPkg = pkg: version: self.callPackage "/home/bergey/code/nixHaskellVersioned/${pkg}/${version}.nix" {};
        # required, not in Nix
        # newer versions
        # HEAD packages        
        monoidExtras = self.callPackage ../../../monoid-extras {};
        active = self.callPackage ../../../active {};
        diagramsCore = self.callPackage ../../../core {};
        diagramsLib = self.callPackage ../../../lib {};
        diagramsCairo = self.callPackage ../../../cairo {};
        diagramsPostscript = self.callPackage ../../../postscript {};
        diagramsSvg = self.callPackage ../../../svg {};
        # self
        diagramsBuilder = self.callPackage ./. {};
      };
    };
         in pkgs.lib.overrideDerivation hs.diagramsBuilder (attrs: {
                buildInputs = [hs.cabalInstall ] ++ attrs.buildInputs;
 })
