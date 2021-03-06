{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}

module ExHack.Hackage.IntegrationHackageSpec (spec) where

import           Data.FileEmbed           (embedFile)
import           Data.List                (isSuffixOf)
import           Data.Maybe               (fromJust, isNothing)
import qualified Data.Text.IO             as T (readFile)
import           System.Directory         (createDirectory, listDirectory,
                                           makeAbsolute,
                                           removeDirectoryRecursive)
import           System.FilePath          (equalFilePath, (</>))
import           Test.Hspec               (Spec, before, describe, it, shouldBe,
                                           shouldSatisfy)

import           ExHack.Cabal.CabalParser (parseCabalFile)
import           ExHack.Hackage.Hackage   (PackageExports (..),
                                           getPackageExports,
                                           unpackHackageTarball)
import           ExHack.ProcessingSteps   (genGraphDep, generateDb,
                                           generateHtmlPages, indexSymbols,
                                           retrievePkgsExports, saveGraphDep)
import           ExHack.Stackage.Stack    (buildPackage)
import           ExHack.Types             (CabalFilesDir (..), Config (..),
                                           DatabaseStatus (..), HtmlDir (..),
                                           ModuleName, PackageDesc (..),
                                           PackageDlDesc (..),
                                           PackageFilePath (..),
                                           StackageFile (..), SymName,
                                           TarballsDir (..), WorkDir (..),
                                           newDatabaseHandle, runStep)



spec :: Spec
spec = do
    describe "hackage" $ do
        it "should extract the content of a tarball" $ do
          (PackageFilePath r) <- unpackHackageTarball workDir $(embedFile "./test/integration/fixtures/tarballs/timeit.tar.gz")
          expected <- makeAbsolute $ workDir </> "timeit-1.0.0.0/"
          r `shouldSatisfy` equalFilePath expected 
        it "should build a tarball" $ do
          tbp <- unpackHackageTarball workDir $(embedFile "./test/integration/fixtures/tarballs/timeit.tar.gz")
          d <- buildPackage tbp
          d `shouldSatisfy` isNothing
        it "should retrieve timeIt exports" $ do
          tbp <- unpackHackageTarball workDir $(embedFile "./test/integration/fixtures/tarballs/timeit.tar.gz")
          _ <- buildPackage tbp
          pd <- getPackageDesc tbp
          let p = fromJust $ parseCabalFile $ fromJust pd 
          exports <- getPackageExports tbp p
          exports `shouldBe` [("System.TimeIt", ["timeIt", "timeItT"])]
          -- Currently broken, see stack init problem.
        it "should retrieve text exports" $ do
          tbp <- unpackHackageTarball workDir $(embedFile "./test/integration/fixtures/tarballs/text.tar.gz")
          _ <- buildPackage tbp
          pd <- getPackageDesc tbp
          let p = fromJust $ parseCabalFile $ fromJust pd
          exports <- getPackageExports tbp p
          exports `shouldBe` textExports 
        it "should retrieve statevar exports" $ do
          tbp <- unpackHackageTarball workDir $(embedFile "./test/integration/fixtures/tarballs/StateVar.tar.gz")
          _ <- buildPackage tbp
          pd <- getPackageDesc tbp
          let p = fromJust $ parseCabalFile $ fromJust pd
          exports <- getPackageExports tbp p
          exports `shouldBe` statevarExports
    before cleanWorkdir $ describe "processing steps" $
        it "should perform a e2e run with a reduced set of packages" $ do
            _ <- unpackHackageTarball workDir $(embedFile "./test/integration/fixtures/tarballs/timeit.tar.gz")
            _ <- unpackHackageTarball workDir $(embedFile "./test/integration/fixtures/tarballs/BiobaseNewick.tar.gz")
            let descs = [PackageDlDesc ("text", "dontcare", "dontcare"), 
                         PackageDlDesc ("BiobaseNewick", "dontcare", "dontcare")] 
                c = testConf :: Config 'New
            dbInit <- runStep generateDb c
            let ci = c {_dbHandle= dbInit} :: Config 'Initialized
            pkgs <- runStep (genGraphDep descs) ci
            dbGraph <- runStep (saveGraphDep pkgs) ci
            let cg = c {_dbHandle=dbGraph} :: Config 'DepsGraph
            dbExprt <- runStep (retrievePkgsExports pkgs) cg
            let ce = cg {_dbHandle=dbExprt} :: Config 'PkgExports
            dbIdx <- runStep (indexSymbols pkgs) ce
            let cidx = ce {_dbHandle=dbIdx} :: Config 'IndexedSyms
            runStep generateHtmlPages cidx
            pure ()

getPackageDesc ::  
  PackageFilePath -- ^ 'FilePath' that may contain a tarball. 
  -> IO (Maybe PackageDesc)
getPackageDesc pfp@(PackageFilePath fp) = do
  f <- Just <$> listDirectory fp
  let mcfp = f >>= getCabalFp >>= \case
        [] -> Nothing
        a  -> Just $ head a
  case mcfp of
    Nothing -> pure Nothing
    Just cfp -> do
      fcontent <- T.readFile (fp </> cfp)
      pure . Just $ PackageDesc (pfp, fcontent)
  where
    -- Filters .cabal files out of a list of files.
    getCabalFp = Just <$> filter (isSuffixOf ".cabal")

cleanWorkdir :: IO ()
cleanWorkdir = do
    removeDirectoryRecursive workDir
    removeDirectoryRecursive htmlDir
    createDirectory workDir
    createDirectory htmlDir

testConf :: Config 'New
testConf = Config (newDatabaseHandle $ workDir </> "test-db.sqlite")
                  (StackageFile "")
                  (TarballsDir $ fixturesDir </> "tarballs")
                  (CabalFilesDir  $ fixturesDir </> "cabal")
                  (WorkDir workDir)
                  (HtmlDir htmlDir)

htmlDir :: FilePath
htmlDir = "./test/integration/output/"

fixturesDir :: FilePath
fixturesDir = "./test/integration/fixtures/"

workDir :: FilePath
workDir = "./test/integration/workdir/"

statevarExports :: [(ModuleName, [SymName])]
statevarExports = [("Data.StateVar",["$=!", "makeGettableStateVar", "makeSettableStateVar", "makeStateVar", "mapStateVar", "GettableStateVar", "HasGetter", "HasSetter", "HasUpdate", "SettableStateVar", "StateVar"])]


textExports :: [(ModuleName, [SymName])]
textExports = [("Data.Text",["empty","Text","singleton","unpack","unpackCString#","all","any","append","break","breakOn","breakOnAll","breakOnEnd","center","chunksOf","commonPrefixes","compareLength","concat","concatMap","cons","copy","count","drop","dropAround","dropEnd","dropWhile","dropWhileEnd","filter","find","findIndex","foldl","foldl'","foldl1","foldl1'","foldr","foldr1","group","groupBy","head","index","init","inits","intercalate","intersperse","isInfixOf","isPrefixOf","isSuffixOf","justifyLeft","justifyRight","last","length","lines","map","mapAccumL","mapAccumR","maximum","minimum","null","pack","partition","replace","replicate","reverse","scanl","scanl1","scanr","scanr1","snoc","span","split","splitAt","splitOn","strip","stripEnd","stripPrefix","stripStart","stripSuffix","tail","tails","take","takeEnd","takeWhile","takeWhileEnd","toCaseFold","toLower","toTitle","toUpper","transpose","uncons","unfoldr","unfoldrN","unlines","unsnoc","unwords","words","zip","zipWith"]),("Data.Text.Array",["copyI","copyM","empty","equal","new","run","run2","toList","unsafeFreeze","unsafeIndex","unsafeWrite","Array","MArray"]),("Data.Text.Encoding",["decodeASCII","decodeLatin1","decodeUtf16BE","decodeUtf16BEWith","decodeUtf16LE","decodeUtf16LEWith","decodeUtf32BE","decodeUtf32BEWith","decodeUtf32LE","decodeUtf32LEWith","decodeUtf8","decodeUtf8'","decodeUtf8With","encodeUtf16BE","encodeUtf16LE","encodeUtf32BE","encodeUtf32LE","encodeUtf8","encodeUtf8Builder","encodeUtf8BuilderEscaped","streamDecodeUtf8","streamDecodeUtf8With","Decoding"]),("Data.Text.Encoding.Error",["ignore","lenientDecode","replace","strictDecode","strictEncode","OnDecodeError","OnEncodeError","OnError","UnicodeException"]),("Data.Text.Foreign",["lengthWord16","asForeignPtr","dropWord16","fromPtr","peekCStringLen","takeWord16","unsafeCopyToPtr","useAsPtr","withCStringLen","I16"]),("Data.Text.IO",["appendFile","getContents","getLine","hGetChunk","hGetContents","hGetLine","hPutStr","hPutStrLn","interact","putStr","putStrLn","readFile","writeFile"]),("Data.Text.Internal",["empty","empty_","firstf","mul","mul32","mul64","safe","showText","text","textP","Text"]),("Data.Text.Internal.Builder",["append'","ensureFree","flush","fromLazyText","fromString","fromText","singleton","toLazyText","toLazyTextWith","writeN","Builder"]),("Data.Text.Internal.Builder.Functions",["<>","i2d"]),("Data.Text.Internal.Builder.Int.Digits",["digits"]),("Data.Text.Internal.Builder.RealFloat.Functions",["roundTo"]),("Data.Text.Internal.Encoding.Fusion",["restreamUtf16BE","restreamUtf16LE","restreamUtf32BE","restreamUtf32LE","streamASCII","streamUtf16BE","streamUtf16LE","streamUtf32BE","streamUtf32LE","streamUtf8","unstream"]),("Data.Text.Internal.Encoding.Fusion.Common",["restreamUtf16BE","restreamUtf16LE","restreamUtf32BE","restreamUtf32LE"]),("Data.Text.Internal.Encoding.Utf16",["chr2","validate1","validate2"]),("Data.Text.Internal.Encoding.Utf32",["validate"]),("Data.Text.Internal.Encoding.Utf8",["chr2","chr3","chr4","ord2","ord3","ord4","validate1","validate2","validate3","validate4"]),("Data.Text.Internal.Functions",["intersperse"]),("Data.Text.Internal.Fusion",["Step","Stream","countChar","findIndex","index","length","mapAccumL","reverse","reverseScanr","reverseStream","stream","unfoldrN","unstream"]),("Data.Text.Internal.Fusion.CaseMapping",["foldMapping","lowerMapping","titleMapping","upperMapping"]),("Data.Text.Internal.Fusion.Common",["all","any","append","compareLengthI","concat","concatMap","cons","countCharI","drop","dropWhile","elem","filter","findBy","findIndexI","foldl","foldl'","foldl1","foldl1'","foldr","foldr1","head","indexI","init","intercalate","intersperse","isPrefixOf","isSingleton","justifyLeftI","last","lengthI","map","maximum","minimum","null","replicateCharI","replicateI","scanl","singleton","snoc","streamCString#","streamList","tail","take","takeWhile","toCaseFold","toLower","toTitle","toUpper","uncons","unfoldr","unfoldrNI","unstreamList","zipWith"]),("Data.Text.Internal.Fusion.Size",["betweenSize","charSize","codePointsSize","compareSize","exactSize","exactly","isEmpty","larger","lowerBound","maxSize","smaller","unionSize","unknownSize","upperBound","Size"]),("Data.Text.Internal.Fusion.Types",["empty","CC","PairS","RS","Scan","Step","Stream"]),("Data.Text.Internal.IO",["hGetLineWith","readChunk"]),("Data.Text.Internal.Lazy",["chunk","chunkOverhead","defaultChunkSize","empty","foldlChunks","foldrChunks","lazyInvariant","showStructure","smallChunkSize","strictInvariant","Text"]),("Data.Text.Internal.Lazy.Encoding.Fusion",["restreamUtf16BE","restreamUtf16LE","restreamUtf32BE","restreamUtf32LE","streamUtf16BE","streamUtf16LE","streamUtf32BE","streamUtf32LE","streamUtf8","unstream"]),("Data.Text.Internal.Lazy.Fusion",["countChar","index","length","stream","unfoldrN","unstream","unstreamChunks"]),("Data.Text.Internal.Lazy.Search",["indices"]),("Data.Text.Internal.Private",["runText","span_"]),("Data.Text.Internal.Read",["digitToInt","hexDigitToInt","perhaps","IParser","IReader","T"]),("Data.Text.Internal.Search",["indices"]),("Data.Text.Internal.Unsafe",["inlineInterleaveST","inlinePerformIO"]),("Data.Text.Internal.Unsafe.Char",["ord","unsafeChr","unsafeChr32","unsafeChr8","unsafeWrite"]),("Data.Text.Internal.Unsafe.Shift",["UnsafeShift"]),("Data.Text.Lazy",["empty","foldlChunks","foldrChunks","Text","all","any","append","break","breakOn","breakOnAll","breakOnEnd","center","chunksOf","commonPrefixes","compareLength","concat","concatMap","cons","count","cycle","drop","dropAround","dropEnd","dropWhile","dropWhileEnd","filter","find","foldl","foldl'","foldl1","foldl1'","foldr","foldr1","fromChunks","fromStrict","group","groupBy","head","index","init","inits","intercalate","intersperse","isInfixOf","isPrefixOf","isSuffixOf","iterate","justifyLeft","justifyRight","last","length","lines","map","mapAccumL","mapAccumR","maximum","minimum","null","pack","partition","repeat","replace","replicate","reverse","scanl","scanl1","scanr","scanr1","singleton","snoc","span","split","splitAt","splitOn","strip","stripEnd","stripPrefix","stripStart","stripSuffix","tail","tails","take","takeEnd","takeWhile","takeWhileEnd","toCaseFold","toChunks","toLower","toStrict","toTitle","toUpper","transpose","uncons","unfoldr","unfoldrN","unlines","unpack","unsnoc","unwords","words","zip","zipWith"]),("Data.Text.Lazy.Builder",["flush","fromLazyText","fromString","fromText","singleton","toLazyText","toLazyTextWith","Builder"]),("Data.Text.Lazy.Builder.Int",["decimal","hexadecimal"]),("Data.Text.Lazy.Builder.RealFloat",["formatRealFloat","realFloat","FPFormat"]),("Data.Text.Lazy.Encoding",["decodeASCII","decodeLatin1","decodeUtf16BE","decodeUtf16BEWith","decodeUtf16LE","decodeUtf16LEWith","decodeUtf32BE","decodeUtf32BEWith","decodeUtf32LE","decodeUtf32LEWith","decodeUtf8","decodeUtf8'","decodeUtf8With","encodeUtf16BE","encodeUtf16LE","encodeUtf32BE","encodeUtf32LE","encodeUtf8","encodeUtf8Builder","encodeUtf8BuilderEscaped"]),("Data.Text.Lazy.IO",["appendFile","getContents","getLine","hGetContents","hGetLine","hPutStr","hPutStrLn","interact","putStr","putStrLn","readFile","writeFile"]),("Data.Text.Lazy.Internal",["chunk","chunkOverhead","defaultChunkSize","empty","foldlChunks","foldrChunks","lazyInvariant","showStructure","smallChunkSize","strictInvariant","Text"]),("Data.Text.Lazy.Read",["decimal","double","hexadecimal","rational","signed","Reader"]),("Data.Text.Read",["decimal","double","hexadecimal","rational","signed","Reader"]),("Data.Text.Unsafe",["inlineInterleaveST","inlinePerformIO","unsafeDupablePerformIO","dropWord16","iter","iter_","lengthWord16","reverseIter","reverseIter_","takeWord16","unsafeHead","unsafeTail","Iter"])]
