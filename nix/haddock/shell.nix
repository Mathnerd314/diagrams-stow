{ pkgs ? import <nixpkgs> {}, haskellPackages ? pkgs.haskellPackages }:

let 
  tmpHaskellPkgs= haskellPackages.override {
        extension = self: super: {
        # required, not in Nix
        fsnotify = self.callPackage /home/bergey/code/nixHaskellVersioned/fsnotify/0.1.0.3.nix {};
        optparseApplicative = self.callPackage /home/bergey/code/nixHaskellVersioned/optparse-applicative/0.11.0.1.nix {};
        tasty = self.callPackage /home/bergey/code/nixHaskellVersioned/tasty/0.10.0.2.nix {};
        haskellSrcExts = self.callPackage /home/bergey/code/nixHaskellVersioned/haskell-src-exts/1.16.0.nix {};
        hlint= self.callPackage /home/bergey/code/nixHaskellVersioned/hlint/1.9.5.nix {};
        lens = pkgs.lib.overrideDerivation super.lens (attrs: {
              doCheck = false;
            });
        # HEAD packages
        monoidExtras = self.callPackage ../../../monoid-extras {};
        active = self.callPackage ../../../active {};
        diagramsCore = self.callPackage ../../../core {};
        diagramsLib = self.callPackage ../../../lib {};
        diagramsSvg = self.callPackage ../../../svg {};
        diagramsBuilder = self.callPackage ../../../builder {};
        # self
        diagramsHaddock= self.callPackage ./. {};
      };
    };
  in let
     haskellPackages = tmpHaskellPkgs;
     in pkgs.lib.overrideDerivation haskellPackages.diagramsHaddock (attrs: {
       buildInputs = [ haskellPackages.cabalInstall ] ++ attrs.buildInputs;
 })
