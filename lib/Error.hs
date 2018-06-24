module Error where

import "rio" RIO

import "lens" Control.Lens  (Prism', prism)
import "base" System.Exit   (exitFailure)
import "parsec" Text.Parsec (ParseError)

import qualified "this" Export
import qualified "this" Module
import qualified "this" Name

data Error
  = Export !Export.Error
  | Name !Name.Error
  | Module !Module.Error
  | Parse !ParseError

instance Export.IsEmptyExplicitExports Error where
  _EmptyExplicitExports = Export._Error.Export._EmptyExplicitExports

instance Export.IsInstanceExported Error where
  _InstanceExported = Export._Error.Export._InstanceExported

instance Export.IsInvalidExport Error where
  _InvalidExport = Export._Error.Export._InvalidExport

instance Export.IsReExportExported Error where
  _ReExportExported = Export._Error.Export._ReExportExported

instance Export.IsError Error where
  _Error = prism Export $ \case
    Export x -> Right x
    x -> Left x

instance Module.IsNotImplemented Error where
  _NotImplemented = Module._Error . Module._NotImplemented

instance Module.IsError Error where
  _Error = prism Module $ \case
    Module x -> Right x
    x -> Left x

instance Name.IsError Error where
  _Error = prism Name $ \case
    Name x -> Right x
    x -> Left x

instance Name.IsMissing Error where
  _Missing = Name._Error . Name._Missing

class
  ( Export.IsError error
  , Module.IsNotImplemented error
  , IsParseError error
  ) =>
  IsError error where
    _Error :: Prism' error Error

instance IsError Error where
  _Error = prism id Right

class IsParseError error where
  _ParseError :: Prism' error ParseError

instance IsParseError ParseError where
  _ParseError = prism id Right

instance IsParseError Error where
  _ParseError = prism Parse $ \case
    Parse x -> Right x
    x -> Left x

errors :: (HasLogFunc env, MonadIO f, MonadReader env f) => Error -> f a
errors = \case
  Export err -> do
    logError "Problem converting the exports"
    logError (display err)
    liftIO exitFailure
  Name err -> do
    logError "Problem converting a name"
    logError (display err)
    liftIO exitFailure
  Module (Module.NotImplemented err) -> do
    logError (display err)
    logError "Report this to https://gitlab.com/joneshf/purty"
    liftIO exitFailure
  Parse err -> do
    logError "Problem parsing module"
    logError (displayShow err)
    liftIO exitFailure
