{-# LANGUAGE OverloadedStrings #-}

module ExHack.ModulePaths (
    modName,
    findComponentRoot,
    toModFilePath
) where

import           Control.Monad           (filterM)
import           Control.Monad.Catch     (MonadThrow, throwM)
import           Control.Monad.IO.Class  (MonadIO, liftIO)
import           Data.List               (intercalate)
import           Distribution.ModuleName (ModuleName, components, toFilePath)
import           System.Directory        (doesPathExist)
import           System.FilePath         ((<.>), (</>))

import           ExHack.Types            (ComponentRoot (..),
                                          PackageFilePath (..),
                                          PackageLoadError (..))

modName :: ModuleName -> String
modName mn = intercalate "." $ components mn

toModFilePath :: PackageFilePath -> ComponentRoot -> ModuleName -> FilePath
toModFilePath (PackageFilePath pfp) (ComponentRoot cr) mn = 
    pfp </> cr </> toFilePath mn <> ".hs"

findComponentRoot :: (MonadIO m, MonadThrow m) => [ComponentRoot] -> ModuleName -> m ComponentRoot  
findComponentRoot croots mn = do
    xs <- filterM testPath (ComponentRoot "./" : croots)
    if length xs == 1
       then pure $ head xs
       else throwM $ CannotFindModuleFile mn croots
  where
    testPath (ComponentRoot p) = liftIO $ doesPathExist (p <> toFilePath mn <.> "hs")  