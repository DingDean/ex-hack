{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module ExHack.Types (
    Config(..),
    ComponentRoot(..),
    PackageComponent(..),
    Package(..),
    PackageIdentifier(..),
    PackageName,
    PackageDlDesc(..),
    TarballDesc(..),
    ModuleName(..),
    SymbolName(..),
    DatabaseHandle,
    DatabaseStatus(..),
    StackageFile(..),
    TarballsDir(..),
    CabalFilesDir(..),
    WorkDir(..),
    PackageExports(..),
    MonadLog(..),
    MonadStep,
    Step,
    tarballsDir,
    cabalFilesDir,
    workDir,
    runStep,
    mkPackageName,
    mkVersion,
    getName,
    getModName,
    depsNames,
    packagedlDescName,
    fromComponents
) where

import Prelude hiding (replicate, length)

import Control.Lens.TH (makeLenses)
import Control.Monad.Catch (MonadMask)
import Control.Monad.Reader (ReaderT, MonadReader, 
                             runReaderT)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Set (Set, toList)
import Data.Text (Text, pack, intercalate, replicate, length)
import qualified Data.Text.IO as TIO (putStrLn, hPutStrLn) 
import Data.String (IsString)
import Database.Selda (RowID, SeldaM)
import Distribution.ModuleName (ModuleName(..), fromComponents, components)
import Distribution.Types.PackageId (PackageIdentifier(..), pkgName)
import Distribution.Types.PackageName (PackageName, unPackageName, mkPackageName)
import Distribution.Version (mkVersion)
import System.FilePath (FilePath)
import System.IO (stderr)

import ExHack.Utils (Has(..))

newtype ComponentRoot = ComponentRoot FilePath
    deriving (IsString, Eq, Show)

data PackageComponent = PackageComponent {
    mods :: [ModuleName],
    root :: [ComponentRoot]
} deriving (Eq, Show)

data Package = Package {
  name :: PackageIdentifier,
  deps :: Set PackageName,
  cabalFile :: Text,
  tarballPath :: FilePath,
  exposedModules :: Maybe PackageComponent,
  dbId :: Maybe RowID,
  allModules :: [PackageComponent]
} deriving (Eq, Show)

type DatabaseHandle (a :: DatabaseStatus) = FilePath

newtype TarballsDir = TarballsDir FilePath
newtype CabalFilesDir = CabalFilesDir FilePath
newtype WorkDir = WorkDir FilePath

data DatabaseStatus = New | Initialized | DepsGraph | PkgExports

newtype StackageFile = StackageFile Text

data Config a = Config {
    _dbHandle :: DatabaseHandle a,
    _stackageFile :: StackageFile,
    _tarballsDir :: TarballsDir,
    _cabalFilesDir :: CabalFilesDir,
    _workDir :: WorkDir
}

makeLenses ''Config

instance Has (Config 'New) (DatabaseHandle 'New) where
    hasLens = dbHandle

instance Has (Config 'Initialized) (DatabaseHandle 'Initialized) where
    hasLens = dbHandle

instance Has (Config a) StackageFile where
    hasLens = stackageFile

instance Has (Config a) TarballsDir where
    hasLens = tarballsDir

instance Has (Config a) CabalFilesDir where
    hasLens = cabalFilesDir

instance Has (Config a) WorkDir where
    hasLens = workDir

-- | Intermediate package description used till we parse the data necessary
--   to generate the proper package description.
-- 
--   (packageName, cabalUrl, tarballUrl)
newtype PackageDlDesc = PackageDlDesc (Text,Text,Text)

-- | Informations extracted from a package entry not yet extracted from its tarball.
--
-- Two elements:
--
--   * Filepath to the tarball.
--   * The cabal file of this package.
--
newtype TarballDesc = TarballDesc (FilePath, Text)

newtype SymbolName = SymbolName Text
    deriving (Show, Eq, IsString)

class (Monad m) => MonadLog m where
    logInfo, logError, logTitle :: Text -> m ()
    logTitle txt = line >> logInfo ("* " <> txt <> " *") >> line
        where !line = logInfo (replicate (length txt + 4) "*")

instance (MonadIO m) => MonadLog (MonadStep c m) where
    logInfo = liftIO . TIO.putStrLn
    logError = liftIO . TIO.hPutStrLn stderr

instance MonadLog SeldaM where
    logInfo = liftIO . TIO.putStrLn
    logError = liftIO . TIO.hPutStrLn stderr

type MonadStep c m = (MonadIO m, MonadMask m, MonadReader c m, MonadLog m)

type Step c a = ReaderT c IO a

-- | Type containing a package exported symbols.
--
-- Three elements:
--
-- * A Package database id.
-- * For each module:
--     * A name.
--     * A list containing the exported symbols.
newtype PackageExports = PackageExports (Package, [(ModuleName, [SymbolName])])
  deriving (Show, Eq)

runStep :: Step c a -> c -> IO a
runStep = runReaderT

packagedlDescName :: PackageDlDesc -> Text
packagedlDescName (PackageDlDesc (n, _, _)) = n

getName :: Package -> Text
getName = pack . unPackageName . pkgName . name

depsNames :: Package -> [String]
depsNames pkg = unPackageName <$> toList (deps pkg)

getModName :: ModuleName -> Text
getModName x = intercalate "." (pack <$> components x)
