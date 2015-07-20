{-# LANGUAGE ExtendedDefaultRules #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE UndecidableInstances #-}

-- | Bump upper bounds in .cabal files, update changelogs, commit to git.

module Main where

import           Control.Lens
import           Control.Monad
import           Control.Monad.Trans.Reader
import           Data.Foldable
import           Data.List.Split                       (splitWhen)
import qualified Data.Map.Strict                       as M
import           Data.Semigroup
import           Data.Text                             (Text)
import qualified Data.Text                             as T
import qualified Distribution.Package                  as C
import qualified Distribution.PackageDescription.Parse as C
import qualified Distribution.Verbosity                as C
import qualified Distribution.Version                  as C
import qualified Filesystem.Path.CurrentOS             as FP
import qualified Options.Applicative                   as O
import qualified Options.Applicative.Types             as O
import           Shelly
import           Text.Trifecta

import           GitConfig

-- TODO imports for GHC < 7.10?

import           Prelude                               hiding (FilePath)

main :: IO ()
main = do
    config <- O.execParser helpParser
    shelly $ runActions config

runActions :: Config -> Sh ()
runActions config = do
    goals <- if (doCabal config)
                -- only modify / commit repos with this dependency
             then filterM (needsUpdate $ package config) (repos config)
                  -- assume user has already restricted to the modified repos
             else return $ repos config
    when (doCabal config) $ updateGoals goals (package config)
    when (doClean config) $ cleanSandbox
    when (doBuild config) $ cabalBuild goals
    when (doCommitCabal config) $ traverse_ (commitCabalChanges $ package config) goals
    when (doCommitChangelog config) $ traverse_ commitChangelog goals
    when (doCommitVersion config) $ traverse_ commitVersionBump goals
    echo "The following packages were modified:"
    echo $ T.unwords $ map toTextIgnore goals

data Config = Config
              { package           :: Package -- -p
              , repos             :: [FilePath]
              , doCabal           :: Bool -- -d
              , doClean           :: Bool -- -l
              , doBuild           :: Bool -- -b
              , doCommitCabal     :: Bool -- -g
              , doCommitChangelog :: Bool -- c
              , doCommitVersion   :: Bool -- V
              }

data Package = Pkg
               { name    :: Text
               , version :: Text
               }

cliParser :: O.Parser Config
cliParser = Config
            <$> O.option parsePackage (O.long "package" <> O.short 'p' <> O.help "the new upper bound, like lens<4.12")
            <*> O.many (O.argument parseFilepath (O.help "a directory with a .cabal file" <> O.metavar "DIR"))
            <*> O.switch (O.long "cabal" <> O.short 'd' <> O.help "update .cabal files with the new dependency")
            <*> O.switch (O.long "clean" <> O.short 'l' <> O.help "delete a cabal sandbox in the current working directory, and restore, preserving add-source dependencies")
            <*> O.switch (O.long "build" <> O.short 'b' <> O.help "cabal install the specified directories")
            <*> O.switch (O.long "git" <> O.short 'g' <> O.help "Commit all changes, with a message about package bounds")
            <*> O.switch (O.long  "changes" <> O.short 'c' <> O.help "update Changelog, commit")
            <*> O.switch (O.long "bump" <> O.short 'V' <> O.help "bump version & commit")

instance Monoid (O.Mod f a) => Semigroup (O.Mod f a) where
    (<>) = mappend

instance Monoid (O.InfoMod a) => Semigroup (O.InfoMod a) where
    (<>) = mappend

helpParser :: O.ParserInfo Config
helpParser = O.info (O.helper <*> cliParser)
             (O.fullDesc
              <> O.progDesc "upper-bounds automates several repetitive parts of point releases for new versions of dependencies.  It is especially intended for a large set of packages which depend on eachother or on the same upstream packages.  It is opinionated by design - the commit message format is hardcoded, for example.  Typical usage is to call with --cabal, verify that everything builds, then call with --git.  It is also possible to run multiple actions in a single invocation.  In this case, the actions are always run in the same order, regardless of the order in which they appear on the commandline."
             <> O.header "upper-bounds - point release automation for Haskell")

-- TODO more validation that this looks like a package constraint
parsePackage :: O.ReadM Package
parsePackage = O.ReadM . asks $ \input ->
  let (n, v) = break (== '<') input in
   Pkg (T.pack n) (T.pack $ tail v)

parseFilepath :: O.ReadM FP.FilePath
parseFilepath = O.ReadM . asks $ FP.fromText . T.pack

formatPkg :: Package -> Text
formatPkg (Pkg n v) = mconcat [n, "-", v]

cabalFilename :: FilePath -> Sh FilePath
cabalFilename repo = do
    files <- ls repo
    case filter (`FP.hasExtension` "cabal") files of
      (fn:_) -> return fn
      _ -> errorExit $ "Could not find .cabal file in: " <> toTextIgnore repo

-- | Test whether a given repo needs updating for the given package and version
needsUpdate :: Package -> FilePath -> Sh Bool
needsUpdate (Pkg pkg v) repo = errExit False $ do
    fn <- cabalFilename repo
    match <- cmd "grep" (pkg <> ".*<") fn
    exit <- lastExitCode
    case exit of
      1 -> return False
    -- pkg is used, but maybe all the lines are up to date
      0 -> return . not $ all (v `T.isInfixOf`) (T.lines match)
      _ -> errorExit $ "grep exited with code " <> (T.pack . show $ exit)

updateGoals :: [FilePath] -> Package -> Sh ()
updateGoals goals pkg = do
    echo "preparing to update .cabal files for:"
    echo $ T.unwords $ map toTextIgnore goals
    traverse_ (updateCabal pkg) goals

-- | Modify a cabal file in place
updateCabal :: Package -> FilePath -> Sh ()
updateCabal (Pkg pkg v) repo = do
    fn <- cabalFilename repo
    -- TODO Don't use regexen
    sed_ ["s/\\(", pkg, ".*\\)< [0-9\\.]*/\\1< ", v, "/"] fn

sed_ :: [Text] -> FilePath -> Sh ()
sed_ parts fn = cmd "sed" "-i" (mconcat parts) fn

cabal_ :: Text -> [Text] -> Sh ()
cabal_ = command1_ "cabal" []

cabal :: Text -> [Text] -> Sh Text
cabal = command1 "cabal" []

createSandbox  :: Sh ()
createSandbox = cabal_ "sandbox" ["init"]

addSource :: [Text] -> Sh ()
addSource [] = return ()
addSource dirs = command_ "cabal" ["sandbox", "add-source"] dirs

getAddSource :: Sh [Text]
getAddSource = do
    inSandbox <- test_f "cabal.sandbox.config"
    if inSandbox then do
        cout <- cabal "sandbox" ["list-sources"]
        return $ case splitWhen T.null (T.lines cout) of
            (_:dirs: _) -> dirs -- middle of 3
            _ -> []
        else return []

cleanSandbox :: Sh ()
cleanSandbox = do
    dirs <- getAddSource
    cabal_ "sandbox" ["delete"]
    createSandbox
    addSource dirs

cabalBuild :: [FilePath] -> Sh ()
cabalBuild repos =  do
    cabal_ "install" $ map (flip T.snoc '/' . toTextIgnore) repos

today :: Sh Text
-- today = T.strip <$> cmd "date" "+%d %b %Y"
today = T.strip <$> cmd "date" "+%F"

gitCommit :: Text -> Sh ()
gitCommit msg  = cmd "git" "commit" "-am" msg

commitCabalChanges :: Package -> FilePath -> Sh ()
commitCabalChanges pkg repo = chdir repo $ do
    -- .cabal file already changed
    gitCommit $ "cabal: allow " <> formatPkg pkg

getPackageVersion :: FilePath -> Sh C.Version
getPackageVersion repo = do
  fn <- cabalFilename repo
  description <- liftIO $ C.readPackageDescription C.normal . FP.encodeString $ fn
  return $ C.packageVersion description

commitChangelog :: FilePath -> Sh ()
commitChangelog repo' = chdir repo' $ do
    repo <- pwd
    oldVer <- getPackageVersion repo
    let newVer = bumpVersion oldVer
    (clFN, oldCL) <- readChangelog
    date <- today
    mayGitConfig <- parseGitConfig repo
    case mayGitConfig of
     Nothing -> errorExit $ "Could not find git config in " <> toTextIgnore repo
     Just gc -> case M.lookup (Remote "origin") gc >>= M.lookup "url" of
         Nothing -> errorExit $ "Could not find origin URL in git config"
         Just url -> case preview _Success . parseString githubUrl mempty . T.unpack $ url of
             Nothing -> errorExit $ "Could not parse as github URL: " <> url
             Just ghUrl -> do
                 writefile clFN $
                     changelog newVer oldVer date ghUrl oldCL
                 gitCommit $ "CHANGELOG for " <> showVersion newVer

-- commit Changelog before version bump so we can identify oldVer
-- TODO make this more robust, looking more places (git history? tags?) for oldVer
commitVersionBump :: FilePath -> Sh ()
commitVersionBump repo' = chdir repo' $ do
    repo <- pwd
    fn <- cabalFilename repo
    oldVer <- getPackageVersion repo
    let newVer = bumpVersion oldVer
    sed_ ["s/\\(^[Vv]ersion: *\\)[0-9\\.]*/\\1", showVersion newVer, "/"] fn
    gitCommit $ "bump version to " <> showVersion newVer

header :: Text
header = "# Change Log\n"

-- | remove the top header
trimChangelog :: Text -> Text
trimChangelog oldCL = case T.lines oldCL of
    ("# Change Log":rest) -> T.unlines $ dropWhile (\l -> T.strip l == "") rest
    _ -> oldCL

showVersion :: C.Version -> Text
showVersion (C.Version ns _tags) = T.intercalate "." $ map (T.pack . show) ns

bumpVersion :: C.Version -> C.Version
bumpVersion (C.Version ns tags) = C.Version ns' tags where
  ns' = case ns of
      [] -> [0,0,0,1] -- is this possible?
      [a] -> [a,0,0,1]
      [a,b] -> [a,b,0,1]
      [a,b,c] -> [a,b,c,1]
      (a:b:c:d:e) -> (a:b:c:d+1:e)

-- changelog :: C.Version -> Text -> Package -> Text
-- changelog newVer date pkg =
--     mconcat ["## ", showVersion newVer, " (", date, ")\n"
--             , "\n"
--             , "allow ", formatPkg pkg, "\n"
--             , "\n"
--             ]
-- new-style generated from git history
changelog :: C.Version -> C.Version -> Text -> GithubUrl -> Text -> Text
changelog newVer oldVer date (GithubUrl _ user repo) oldCL =
    mconcat ["## [v", showVersion newVer,
             "](https://github.com/", user, "/", repo, "/tree/v", showVersion newVer,
             ") (", date, ")\n\n",
             "[Full Changelog](https://github.com/", user, "/", repo, "/compare/v",
             showVersion oldVer, "...v", showVersion newVer, ")\n\n",
             trimChangelog oldCL
             ]

changelogNames :: FilePath -> Bool
changelogNames fp = e (FP.extension fp) && b (toTextIgnore . FP.basename $ fp)
  where
    e ext = ext `elem` [Nothing, Just "md", Just "markdown"]
    b name = name `elem` ["CHANGES", "CHANGELOG"]

readChangelog :: Sh (FilePath, Text)
readChangelog = do
    dir <- pwd
    fns <- ls dir
    case filter changelogNames fns of
     [] -> errorExit $ "Could not find Changelog in " <> toTextIgnore dir
     [fn] -> do
         contents <- readfile fn
         return (fn, contents)
     fns -> errorExit $ "Could not choose among: " <> T.unwords (map toTextIgnore fns)
