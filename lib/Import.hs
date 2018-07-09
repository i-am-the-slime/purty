module Import where

import "rio" RIO

import "freer-simple" Control.Monad.Freer        (Eff, Member)
import "freer-simple" Control.Monad.Freer.Error  (Error)
import "base" Data.List                          (sortOn)
import "base" Data.List.NonEmpty                 (NonEmpty, nonEmpty)
import "semigroupoids" Data.Semigroup.Foldable   (intercalateMap1)
import "prettyprinter" Data.Text.Prettyprint.Doc
    ( Doc
    , flatAlt
    , group
    , indent
    , line
    , parens
    , space
    , (<+>)
    )

import qualified "purescript" Language.PureScript

import "this" Export (Export)

import qualified "this" Annotation
import qualified "this" Export
import qualified "this" Log
import qualified "this" Name
import qualified "this" Variations

newtype Alias a
  = Alias (Maybe (Name.Module a))
  deriving (Eq, Functor, Ord, Show)

data Explicit a
  = Explicit !a !(Name.Module a) ![Export a] !(Alias a)
  deriving (Functor, Show)

dynamicExplicit :: NonEmpty (Explicit Annotation.Sorted) -> Doc a
dynamicExplicit = \case
  explicits ->
    line
      <> line
      <> intercalateMap1 line go explicits
  where
  go = \case
    Explicit _ann name imports' (Alias alias') ->
      "import" <+> Name.docFromModule name
        <> imports
        <> foldMap (\alias -> space <> "as" <+> Name.docFromModule alias) alias'
      where
      imports =
        group (flatAlt (line <> indent 2 multiLine) (space <> singleLine))
      Variations.Variations { Variations.multiLine, Variations.singleLine } =
        maybe
          (pure $ parens mempty)
          (Variations.parenthesize Export.docFromExport)
          (nonEmpty imports')

sortExplicit :: [Explicit a] -> [Explicit Annotation.Sorted]
sortExplicit = fmap (Annotation.Sorted <$) . sortOn go
  where
  go = \case
    Explicit _ann name _exports _alias -> void name

staticExplicit :: NonEmpty (Explicit Annotation.Sorted) -> Doc a
staticExplicit = \case
  explicits ->
    line
      <> line
      <> intercalateMap1 line go explicits
  where
  go = \case
    Explicit _ann name imports' (Alias alias') ->
      "import" <+> Name.docFromModule name
        <> line
        <> indent 2 imports
        <> foldMap (\alias -> space <> "as" <+> Name.docFromModule alias) alias'
      where
      imports =
        maybe
          (parens line)
          (Variations.multiLine . Variations.parenthesize Export.docFromExport)
          (nonEmpty imports')

data Hiding a
  = Hiding !a !(Name.Module a) ![Export a] !(Alias a)
  deriving (Functor, Show)

dynamicHiding :: NonEmpty (Hiding Annotation.Sorted) -> Doc a
dynamicHiding = \case
  hidings ->
    line
      <> line
      <> intercalateMap1 line go hidings
  where
  go = \case
    Hiding _ann name imports' (Alias alias') ->
      "import"
        <+> Name.docFromModule name
        <+> "hiding"
        <> imports
        <> foldMap (\alias -> space <> "as" <+> Name.docFromModule alias) alias'
      where
      imports =
        group (flatAlt (line <> indent 2 multiLine) (space <> singleLine))
      Variations.Variations { Variations.multiLine, Variations.singleLine } =
        maybe
          (pure $ parens mempty)
          (Variations.parenthesize Export.docFromExport)
          (nonEmpty imports')

sortHiding :: [Hiding a] -> [Hiding Annotation.Sorted]
sortHiding = fmap (Annotation.Sorted <$) . sortOn go
  where
  go = \case
    Hiding _ann name _exports _alias -> void name

staticHiding :: NonEmpty (Hiding Annotation.Sorted) -> Doc a
staticHiding = \case
  hidings ->
    line
      <> line
      <> intercalateMap1 line go hidings
  where
  go = \case
    Hiding _ann name imports' (Alias alias') ->
      "import"
        <+> Name.docFromModule name
        <+> "hiding"
        <> indent 2 imports
        <> foldMap (\alias -> space <> "as" <+> Name.docFromModule alias) alias'
      where
      imports =
        maybe
          (parens line)
          (Variations.multiLine . Variations.parenthesize Export.docFromExport)
          (nonEmpty imports')

data Import a
  = ImportExplicit !(Explicit a)
  | ImportHiding !(Hiding a)
  | ImportOpen !(Open a)
  | ImportQualified !(Qualified a)
  deriving (Functor, Show)

fromPureScript ::
  ( Member (Error Name.Missing) e
  , Member (Error Export.InstanceExported) e
  , Member (Error Export.InvalidExport) e
  , Member (Error Export.ReExportExported) e
  ) =>
  Language.PureScript.Declaration ->
  Eff e (Maybe (Import Annotation.Unannotated))
fromPureScript = \case
  Language.PureScript.ImportDeclaration _ name' (Language.PureScript.Explicit imports') alias' -> do
    name <- Name.module' name'
    imports <- traverse Export.export imports'
    alias <- Alias <$> traverse Name.module' alias'
    let explicit = Explicit Annotation.Unannotated name imports alias
    pure (Just $ ImportExplicit explicit)
  Language.PureScript.ImportDeclaration _ name' (Language.PureScript.Hiding imports') alias' -> do
    name <- Name.module' name'
    imports <- traverse Export.export imports'
    alias <- Alias <$> traverse Name.module' alias'
    let hiding = Hiding Annotation.Unannotated name imports alias
    pure (Just $ ImportHiding hiding)
  Language.PureScript.ImportDeclaration _ name' Language.PureScript.Implicit (Just alias') -> do
    name <- Name.module' name'
    alias <- Alias . Just <$> Name.module' alias'
    let qualified = Qualified Annotation.Unannotated name alias
    pure (Just $ ImportQualified qualified)
  Language.PureScript.ImportDeclaration _ name' Language.PureScript.Implicit Nothing -> do
    name <- Name.module' name'
    let open = Open Annotation.Unannotated name
    pure (Just $ ImportOpen open)
  Language.PureScript.BindingGroupDeclaration {} -> pure Nothing
  Language.PureScript.BoundValueDeclaration {} -> pure Nothing
  Language.PureScript.DataBindingGroupDeclaration {} -> pure Nothing
  Language.PureScript.DataDeclaration {} -> pure Nothing
  Language.PureScript.ExternDataDeclaration {} -> pure Nothing
  Language.PureScript.ExternDeclaration {} -> pure Nothing
  Language.PureScript.ExternKindDeclaration {} -> pure Nothing
  Language.PureScript.FixityDeclaration {} -> pure Nothing
  Language.PureScript.TypeClassDeclaration {} -> pure Nothing
  Language.PureScript.TypeDeclaration {} -> pure Nothing
  Language.PureScript.TypeInstanceDeclaration {} -> pure Nothing
  Language.PureScript.TypeSynonymDeclaration {} -> pure Nothing
  Language.PureScript.ValueDeclaration {} -> pure Nothing

sort :: Imports a -> Sorted
sort = \case
  Imports imports ->
    Sorted
      (nonEmpty $ foldMap (sortOpen . mapMaybe open . toList) imports)
      (nonEmpty $ foldMap (sortHiding . mapMaybe hiding . toList) imports)
      (nonEmpty $ foldMap (sortExplicit . mapMaybe explicit . toList) imports)
      (nonEmpty $ foldMap (sortQualified . mapMaybe qualified . toList) imports)
    where
    explicit = \case
      ImportExplicit x -> Just x
      ImportHiding _ -> Nothing
      ImportOpen _ -> Nothing
      ImportQualified _ -> Nothing
    hiding = \case
      ImportExplicit _ -> Nothing
      ImportHiding x -> Just x
      ImportOpen _ -> Nothing
      ImportQualified _ -> Nothing
    open = \case
      ImportExplicit _ -> Nothing
      ImportHiding _ -> Nothing
      ImportOpen x -> Just x
      ImportQualified _ -> Nothing
    qualified = \case
      ImportExplicit _ -> Nothing
      ImportHiding _ -> Nothing
      ImportOpen _ -> Nothing
      ImportQualified x -> Just x

newtype Imports a
  = Imports (Maybe (NonEmpty (Import a)))
  deriving (Show)

instance (Log.Inspect a) => Log.Inspect (Imports a)

data Open a
  = Open !a !(Name.Module a)
  deriving (Functor, Show)

dynamicOpen :: NonEmpty (Open Annotation.Sorted) -> Doc a
dynamicOpen = \case
  opens ->
    line
      <> intercalateMap1 line go opens
  where
  go = \case
    Open _ann name ->
      "import" <+> Name.docFromModule name

sortOpen :: [Open a] -> [Open Annotation.Sorted]
sortOpen = fmap (Annotation.Sorted <$) . sortOn go
  where
  go = \case
    Open _ann name -> void name

staticOpen :: NonEmpty (Open Annotation.Sorted) -> Doc a
staticOpen = \case
  opens ->
    line
      <> intercalateMap1 line go opens
  where
  go = \case
    Open _ann name ->
      "import" <+> Name.docFromModule name

data Qualified a
  = Qualified !a !(Name.Module a) !(Alias a)
  deriving (Functor, Show)

dynamicQualified :: NonEmpty (Qualified Annotation.Sorted) -> Doc a
dynamicQualified = \case
  qualifieds ->
    line
      <> line
      <> intercalateMap1 line go qualifieds
  where
  go = \case
    Qualified _ann name (Alias alias') ->
      "import"
        <+> Name.docFromModule name
        <> foldMap (\alias -> space <> "as" <+> Name.docFromModule alias) alias'

sortQualified :: [Qualified a] -> [Qualified Annotation.Sorted]
sortQualified = fmap (Annotation.Sorted <$) . sortOn go
  where
  go = \case
    Qualified _ann name _alias -> void name

staticQualified :: NonEmpty (Qualified Annotation.Sorted) -> Doc a
staticQualified = \case
  qualifieds ->
    line
      <> line
      <> intercalateMap1 line go qualifieds
  where
  go = \case
    Qualified _ann name (Alias alias') ->
      "import"
        <+> Name.docFromModule name
        <> foldMap (\alias -> space <> "as" <+> Name.docFromModule alias) alias'

data Sorted
  = Sorted
      !(Maybe (NonEmpty (Open Annotation.Sorted)))
      !(Maybe (NonEmpty (Hiding Annotation.Sorted)))
      !(Maybe (NonEmpty (Explicit Annotation.Sorted)))
      !(Maybe (NonEmpty (Qualified Annotation.Sorted)))
  deriving (Show)

instance Log.Inspect Sorted

dynamic :: Sorted -> Doc b
dynamic x = case x of
  Sorted open hiding explicit qualified ->
    foldMap dynamicOpen open
      <> foldMap dynamicHiding hiding
      <> foldMap dynamicExplicit explicit
      <> foldMap dynamicQualified qualified
      <> trailingLine x

static :: Sorted -> Doc b
static x = case x of
  Sorted open hiding explicit qualified ->
    foldMap staticOpen open
      <> foldMap staticHiding hiding
      <> foldMap staticExplicit explicit
      <> foldMap staticQualified qualified
      <> trailingLine x

trailingLine :: Sorted -> Doc a
trailingLine = \case
  Sorted Nothing Nothing Nothing Nothing -> mempty
  _ -> line
