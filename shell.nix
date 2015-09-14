{ pkgs ? import <nixpkgs> {}, haskellPackages ? pkgs.haskellPackages }:
with pkgs.lib; with import <nixpkgs/pkgs/development/haskell-modules/lib.nix> { inherit pkgs; }; 
let {
  thesepackages = self: {
          diagrams-opengl = self.callPackage ./opengl {};
#          diagrams-openscad = self.callPackage ./openscad {};
#          diagrams-stow = self.callPackage ./stow {};
#          org-babel-diagrams = self.callPackage ./org-babel {};
          SVGFonts = self.callPackage ./SVGFonts {};
          active = self.callPackage ./active {};
          diagrams-backend-tests = self.callPackage ./backend-tests {};
#          diagrams-bench = self.callPackage ./bench {};
          diagrams-builder = self.callPackage ./builder {};
          diagrams-cairo = self.callPackage ./cairo {};
#          diagrams-canvas = self.callPackage ./canvas {};
          diagrams-constraints = self.callPackage ./constraints {};
          diagrams-contrib = self.callPackage ./contrib {};
          diagrams-core = self.callPackage ./core {};
          diagrams-doc = self.callPackage ./doc {};
          diagrams-gtk = self.callPackage ./gtk {};
          diagrams-haddock = self.callPackage ./haddock {};
          diagrams-html5 = self.callPackage ./html5 {};
          diagrams-lib = self.callPackage ./lib {};
#          diagrams-pgf = self.callPackage ./pgf {};
          diagrams-postscript = self.callPackage ./postscript {};
          diagrams-povray = self.callPackage ./povray {};
          diagrams-rasterific = self.callPackage ./rasterific {};
          diagrams-solve = self.callPackage ./solve {};
          diagrams-svg = self.callPackage ./svg {};
          diagrams-test = self.callPackage ./test {};
#          diagrams-travis = self.callPackage ./travis {};
#          docutils = self.callPackage ./docutils {};
          dual-tree = self.callPackage ./dual-tree {};
          force-layout = doJailbreak (self.callPackage ./force-layout {});
          monoid-extras = self.callPackage ./monoid-extras {};
          package-ops = self.callPackage ./package-ops {};
          palette = self.callPackage ./palette {};
          statestack = self.callPackage ./statestack {};
          vector-space-points = self.callPackage ./vector-space-points {};
          linear = doJailbreak (self.callPackage ./upstream/linear {});
  };

  mapUnique = list: attrValues (foldl' (attrs: x: attrs // { ${x.pname} = x; }) {} list);
  
  hs = haskellPackages.override {
        overrides = self: super: {
#            Rasterific = dontCheck super.Rasterific;
#            fingertree = dontCheck super.fingertree;
#            lens = dontCheck super.lens;
#            prelude-extras = dontCheck super.prelude-extras;
          } // thesepackages self;
    };
  xpkgs = thesepackages hs;
  mypackages = attrValues xpkgs;
  upstreamPackages = concatMap (x: x.systemBuildInputs) mypackages;
  hp = concatMap (x: x.haskellBuildInputs) mypackages;
  upstreamHsPackages = mapUnique hp;
  ghc = hs.ghcWithPackages (ps: upstreamHsPackages);

  body = pkgs.stdenv.mkDerivation {
    name = "my-haskell-env-0";
    buildInputs = [ ghc hs.cabal-install ] ++ (with pkgs; [ python33Packages.docutils python33Packages.pygments mr cabal2nix z3 ]) ++ upstreamPackages;
    shellHook = "eval $(egrep ^export ${ghc}/bin/ghc)";
  };
}
