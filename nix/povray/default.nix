# This file was auto-generated by cabal2nix. Please do NOT edit manually!

{ cabal, colour, diagramsCore, diagramsLib, lens, vectorSpace }:

cabal.mkDerivation (self: {
  pname = "diagrams-povray";
  version = "0.1";
  src = ./.;
  buildDepends = [
    colour diagramsCore diagramsLib lens vectorSpace
  ];
  meta = {
    homepage = "http://projects.haskell.org/diagrams";
    description = "Persistence Of Vision raytracer backend for diagrams EDSL";
    license = self.stdenv.lib.licenses.bsd3;
    platforms = self.ghc.meta.platforms;
  };
})
