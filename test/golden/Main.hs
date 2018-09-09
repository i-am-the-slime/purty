{-# LANGUAGE QuasiQuotes #-}
module Main where

import "rio" RIO hiding (encodeUtf8)

import "freer-simple" Control.Monad.Freer
    ( Eff
    , interpretM
    , runM
    )
import "freer-simple" Control.Monad.Freer.Error
    ( Error
    , handleError
    )
import "freer-simple" Control.Monad.Freer.Reader             (Reader, runReader)
import "freer-simple" Data.OpenUnion                         ((:++:))
import "text" Data.Text.Lazy.Encoding                        (encodeUtf8)
import "prettyprinter" Data.Text.Prettyprint.Doc             (LayoutOptions)
import "prettyprinter" Data.Text.Prettyprint.Doc.Render.Text (renderLazy)
import "path" Path
    ( Abs
    , Dir
    , File
    , Path
    , Rel
    , filename
    , parseRelFile
    , reldir
    , toFilePath
    , (</>)
    )
import "path-io" Path.IO                                     (makeAbsolute)
import "tasty" Test.Tasty
    ( TestTree
    , defaultMain
    , testGroup
    )
import "tasty-golden" Test.Tasty.Golden
    ( findByExtension
    , goldenVsStringDiff
    )
import "parsec" Text.Parsec                                  (ParseError)

import "purty" Env (Formatting(Dynamic, Static), defaultLayoutOptions)

import qualified "purty" Declaration.Class
import qualified "purty" Declaration.DataType
import qualified "purty" Declaration.Fixity
import qualified "purty" Declaration.Instance
import qualified "purty" Declaration.Value
import qualified "purty" Error
import qualified "purty" Exit
import qualified "purty" Export
import qualified "purty" File
import qualified "purty" Kind
import qualified "purty" Log
import qualified "purty" Name
import qualified "purty" Purty
import qualified "purty" Type

main :: IO ()
main = do
  tests <- goldenTests
  defaultMain tests

diff :: FilePath -> FilePath -> [String]
diff old new = ["diff", "--unified", old, new]

golden :: Formatting -> Path Rel File -> TestTree
golden formatting goldenFile =
  goldenVsStringDiff (toFilePath goldenFile) diff (toFilePath goldenFile) $ do
    absFile <- makeAbsolute originalFile
    (_, logOptions) <- logOptionsMemory
    withLogFunc logOptions $ \logFunc ->
      runM
        $ runReader defaultLayoutOptions
        $ runReader formatting
        $ interpretM (Log.io logFunc)
        $ interpretM File.io
        $ interpretM Exit.io
        $ flip handleError Error.parseError
        $ Error.type'
        $ Error.name
        $ Error.kind
        $ Error.export
        $ Error.declarationValue
        $ Error.declarationInstance
        $ Error.declarationFixity
        $ Error.declarationDataType
        $ Error.declarationClass
        $ test absFile
  where
  originalFile = [reldir|test/golden/files/original|] </> filename goldenFile

test ::
  Path Abs File ->
  Eff
    ( Declaration.Class.Errors
    :++: Declaration.DataType.Errors
    :++: Declaration.Fixity.Errors
    :++: Declaration.Instance.Errors
    :++: Declaration.Value.Errors
    :++: Export.Errors
    :++: Kind.Errors
    :++: Name.Errors
    :++: Type.Errors
    :++: '[ Error ParseError
          , Exit.Exit
          , File.File
          , Log.Log
          , Reader Formatting
          , Reader LayoutOptions
          , IO
          ]
    )
    LByteString
test absFile = encodeUtf8 . renderLazy <$> Purty.fromAbsFile absFile

goldenTests :: IO TestTree
goldenTests = do
  tests <- sequenceA [dynamic, static]
  pure (testGroup "golden" tests)

dynamic :: IO TestTree
dynamic = do
  files <- goldenFiles [reldir|test/golden/files/dynamic|]
  pure (testGroup "dynamic" $ golden Dynamic <$> files)

static :: IO TestTree
static = do
  files <- goldenFiles [reldir|test/golden/files/static|]
  pure (testGroup "static" $ golden Static <$> files)

goldenFiles :: Path Rel Dir -> IO [Path Rel File]
goldenFiles dir = do
  paths <- findByExtension [".purs"] (toFilePath dir)
  traverse parseRelFile paths
