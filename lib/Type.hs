module Type
  ( Constraint
  , Errors
  , InferredConstraintData
  , InferredForallWithSkolem
  , InferredSkolem
  , InferredType
  , InfixTypeNotTypeOp
  , PrettyPrintForAll
  , PrettyPrintFunction
  , PrettyPrintObject
  , Row(Row)
  , RowPair(RowPair)
  , RowSurround(RowBraces, RowParens)
  , Rowpen(Rowpen, Rowsed)
  , Type(TypeParens, TypeRow, TypeVariable)
  , Variable(Variable)
  , Variables(Variables)
  , constraint
  , doc
  , docFromConstraint
  , docFromRow
  , docFromVariable
  , docFromVariables
  , fromPureScript
  , normalize
  , normalizeConstraint
  , normalizeVariables
  , variables
  ) where

import "rio" RIO hiding (Data)

import "freer-simple" Control.Monad.Freer        (Eff, Members)
import "freer-simple" Control.Monad.Freer.Error  (Error, throwError)
import "base" Data.Bitraversable                 (bitraverse)
import "base" Data.List.NonEmpty                 (NonEmpty((:|)), (<|))
import "semigroupoids" Data.Semigroup.Foldable   (intercalateMap1)
import "prettyprinter" Data.Text.Prettyprint.Doc
    ( Doc
    , braces
    , colon
    , comma
    , dot
    , indent
    , line
    , parens
    , pipe
    , pretty
    , space
    , (<+>)
    )
import "base" GHC.Exts                           (IsList(fromList))
import "purescript" Language.PureScript.PSString (PSString)

import qualified "purescript" Language.PureScript
import qualified "purescript" Language.PureScript.Label

import qualified "this" Annotation
import qualified "this" Kind
import qualified "this" Label
import qualified "this" List
import qualified "this" Name
import qualified "this" Variations

data Constraint a
  = Constraint !(Name.Qualified Name.Class a) !(List.List (Type a))
  deriving (Functor, Show)

constraint ::
  ( Members
    '[ Error InferredConstraintData
     , Error InferredForallWithSkolem
     , Error InferredSkolem
     , Error InferredType
     , Error InfixTypeNotTypeOp
     , Error PrettyPrintForAll
     , Error PrettyPrintFunction
     , Error PrettyPrintObject
     , Error Kind.InferredKind
     , Error Name.Missing
     ]
    e
  ) =>
  Language.PureScript.Constraint ->
  Eff e (Constraint Annotation.Unannotated)
constraint = \case
  Language.PureScript.Constraint x y (Just z) ->
    throwError (InferredConstraintData x y z)
  Language.PureScript.Constraint x' y' Nothing -> do
    x <- Name.qualified (pure . Name.class') x'
    y <- fromList <$> traverse fromPureScript y'
    pure (Constraint x y)

docFromConstraint ::
  Constraint Annotation.Normalized ->
  Variations.Variations (Doc b)
docFromConstraint = pure . \case
  Constraint x y' ->
    Name.docFromQualified Name.docFromClass x
      <> List.list' (\y -> space <> intercalateMap1 space (Variations.singleLine . doc) y) y'

normalizeConstraint :: Constraint a -> Constraint Annotation.Normalized
normalizeConstraint = \case
  Constraint x y -> Constraint (Annotation.None <$ x) (fmap normalize y)

newtype Forall
  = Forall (NonEmpty Variable)
  deriving (Show)

docFromForall :: Forall -> Doc a
docFromForall = \case
  Forall x -> "forall" <+> intercalateMap1 space docFromVariable x <> dot

normalizeForall :: Forall -> Forall -> Forall
normalizeForall x' y' = case (x', y') of
  (Forall x, Forall y) -> Forall (y <> x)

data Row a
  = Row !RowSurround !(List.List (RowPair a)) !(Rowpen a)
  deriving (Functor, Show)

docFromRow :: Row Annotation.Normalized -> Doc a
docFromRow = \case
  Row x y z -> surround (pairs <> rowpen)
    where
    surround = case x of
      RowBraces -> braces
      RowParens -> parens
    pairs = List.list' (intercalateMap1 (comma <> space) docFromRowPair) y
    rowpen = docFromRowpen z

normalizeRow :: Row a -> Row Annotation.Normalized
normalizeRow = \case
  Row surround y z -> Row surround (fmap normalizeRowPair y) (normalizeRowpen z)

row ::
  ( Members
    '[ Error InferredConstraintData
     , Error InferredForallWithSkolem
     , Error InferredSkolem
     , Error InferredType
     , Error InfixTypeNotTypeOp
     , Error PrettyPrintForAll
     , Error PrettyPrintFunction
     , Error PrettyPrintObject
     , Error Kind.InferredKind
     , Error Name.Missing
     ]
    e
  ) =>
  Language.PureScript.Label.Label ->
  Language.PureScript.Type ->
  Language.PureScript.Type ->
  Eff
    e
    (NonEmpty (RowPair Annotation.Unannotated), Rowpen Annotation.Unannotated)
row x' y' = \case
  Language.PureScript.REmpty -> do
    pairs <- pure <$> rowPair x' y'
    pure (pairs, Rowsed)
  Language.PureScript.RCons x y z -> do
    pair <- rowPair x' y'
    (pairs, rowsed) <- row x y z
    pure (pair <| pairs, rowsed)
  z -> do
    pairs <- pure <$> rowPair x' y'
    type' <- fromPureScript z
    pure (pairs, Rowpen type')

data RowSurround
  = RowBraces
  | RowParens
  deriving (Show)

data RowPair a
  = RowPair !Label.Label !(Type a)
  deriving (Functor, Show)

docFromRowPair :: RowPair Annotation.Normalized -> Doc a
docFromRowPair = \case
  RowPair x y -> Label.doc x <+> colon <> colon <+> Variations.singleLine (doc y)

normalizeRowPair :: RowPair a -> RowPair Annotation.Normalized
normalizeRowPair = \case
  RowPair x y -> RowPair x (normalize y)

rowPair ::
  ( Members
    '[ Error InferredConstraintData
     , Error InferredForallWithSkolem
     , Error InferredSkolem
     , Error InferredType
     , Error InfixTypeNotTypeOp
     , Error PrettyPrintForAll
     , Error PrettyPrintFunction
     , Error PrettyPrintObject
     , Error Kind.InferredKind
     , Error Name.Missing
     ]
    e
  ) =>
  Language.PureScript.Label.Label ->
  Language.PureScript.Type ->
  Eff e (RowPair Annotation.Unannotated)
rowPair x y = fmap (RowPair $ Label.fromPureScript x) (fromPureScript y)

data Rowpen a
  = Rowpen !(Type a)
  | Rowsed
  deriving (Functor, Show)

docFromRowpen :: Rowpen Annotation.Normalized -> Doc a
docFromRowpen = \case
  Rowpen x -> space <> pipe <+> Variations.singleLine (doc x)
  Rowsed -> mempty

normalizeRowpen :: Rowpen a -> Rowpen Annotation.Normalized
normalizeRowpen = \case
  Rowpen x -> Rowpen (normalize x)
  Rowsed -> Rowsed

-- |
-- We're using the underlying PureScript representation here,
-- as it handles unicode properly for the language.
newtype Symbol
  = Symbol PSString
  deriving (Show)

docFromSymbol :: Symbol -> Doc a
docFromSymbol = \case
  Symbol x -> pretty (Language.PureScript.prettyPrintString x)

data Type a
  = TypeAnnotation !a !(Type a)
  | TypeApplication !(Type a) !(Type a)
  | TypeConstrained !(Constraint a) !(Type a)
  | TypeForall !Forall !(Type a)
  | TypeFunction !(Type a) !(Type a)
  | TypeInfixOperator !(Type a) !(Name.Qualified Name.TypeOperator a) !(Type a)
  | TypeKinded !(Type a) !(Kind.Kind a)
  | TypeRow !(Row a)
  | TypeParens !(Type a)
  | TypeSymbol !Symbol
  | TypeTypeConstructor !(Name.Qualified Name.TypeConstructor a)
  | TypeTypeOperator !(Name.Qualified Name.TypeOperator a)
  | TypeVariable !Variable
  | TypeWildcard !Wildcard
  deriving (Functor, Show)

normalizeTypeApplication :: Type a -> Type b -> Type Annotation.Normalized
normalizeTypeApplication x' y' = case (x', y') of
  ( TypeApplication
      ( TypeTypeConstructor
        ( Name.Qualified
            (Just (Name.Module (Name.Proper _ "Prim" :| [])))
            (Name.TypeConstructor (Name.Proper _ "Function"))
        )
      )
      x
    , y
    ) -> TypeFunction (normalize x) (normalize y)
  ( TypeTypeConstructor
      ( Name.Qualified
          (Just (Name.Module (Name.Proper _ "Prim" :| [])))
          (Name.TypeConstructor (Name.Proper _ "Record"))
      )
    , TypeRow (Row _ pairs rowpen)
    ) -> TypeRow (normalizeRow $ Row RowBraces pairs rowpen)
  ( TypeTypeConstructor
      ( Name.Qualified
          (Just (Name.Module (Name.Proper _ "Prim" :| [])))
          (Name.TypeConstructor (Name.Proper _ "Record"))
      )
    , y
    ) -> TypeRow (normalizeRow $ Row RowBraces List.Empty $ Rowpen y)
  (_, _) -> TypeApplication (normalize x') (normalize y')

doc :: Type Annotation.Normalized -> Variations.Variations (Doc b)
doc = \case
  TypeAnnotation Annotation.None x -> doc x
  TypeAnnotation Annotation.Braces x -> fmap braces (doc x)
  TypeAnnotation Annotation.Parens x -> fmap parens (doc x)
  TypeApplication x y ->
    pure (Variations.singleLine (doc x) <+> Variations.singleLine (doc y))
  TypeConstrained x y ->
    Variations.Variations { Variations.multiLine, Variations.singleLine }
    where
    multiLine =
      Variations.multiLine (docFromConstraint x) <+> "=>"
        <> line
        <> Variations.multiLine (doc y)
    singleLine =
      Variations.singleLine (docFromConstraint x) <+> "=>"
        <+> Variations.singleLine (doc y)
  TypeForall x y ->
    Variations.Variations { Variations.multiLine, Variations.singleLine }
    where
    multiLine =
      docFromForall x
        <> line
        <> Variations.multiLine (doc y)
    singleLine = docFromForall x <+> Variations.singleLine (doc y)
  TypeFunction x y ->
    Variations.Variations { Variations.multiLine, Variations.singleLine }
    where
    multiLine =
      Variations.multiLine (doc x) <+> "->"
        <> line
        <> Variations.multiLine (doc y)
    singleLine =
      Variations.singleLine (doc x) <+> "->" <+> Variations.singleLine (doc y)
  TypeInfixOperator x y z ->
    Variations.Variations { Variations.multiLine, Variations.singleLine }
    where
    multiLine =
      Variations.multiLine (doc x)
        <> line
        <> indent 2 right
      where
      right =
        Name.docFromQualified Name.docFromTypeOperator y
          <+> Variations.multiLine (doc z)
    singleLine =
      Variations.singleLine (doc x)
        <+> Name.docFromQualified Name.docFromTypeOperator y
        <+> Variations.singleLine (doc z)
  TypeKinded x y ->
    Variations.Variations { Variations.multiLine, Variations.singleLine }
    where
    multiLine =
      Variations.multiLine (doc x) <+> colon <> colon
        <> line
        <> indent 2 (Variations.multiLine $ Kind.doc y)
    singleLine =
      Variations.singleLine (doc x)
        <+> colon
        <> colon
        <+> Variations.singleLine (Kind.doc y)
  TypeRow x -> pure (docFromRow x)
  TypeParens x -> pure (parens $ Variations.singleLine $ doc x)
  TypeSymbol x -> pure (docFromSymbol x)
  TypeTypeConstructor x ->
    pure (Name.docFromQualified Name.docFromTypeConstructor x)
  TypeTypeOperator x ->
    pure (parens (Name.docFromQualified Name.docFromTypeOperator x))
  TypeVariable x -> pure (docFromVariable x)
  TypeWildcard x -> pure (docFromWildcard x)

normalize :: Type a -> Type Annotation.Normalized
normalize = \case
  TypeAnnotation _ann x -> normalize x
  TypeApplication x y -> normalizeTypeApplication x y
  TypeConstrained x y ->
    TypeConstrained (normalizeConstraint x) (normalize y)
  TypeForall x (TypeForall y z) -> normalize (TypeForall (normalizeForall x y) z)
  TypeForall x y -> TypeForall x (normalize y)
  TypeFunction x y -> TypeFunction (normalize x) (normalize y)
  TypeInfixOperator x y z ->
    TypeInfixOperator (normalize x) (Annotation.None <$ y) (normalize z)
  TypeKinded x y -> TypeKinded (normalize x) (Kind.normalize y)
  TypeRow x -> TypeRow (normalizeRow x)
  TypeParens x -> TypeParens (normalize x)
  TypeSymbol x -> TypeSymbol x
  TypeTypeConstructor x -> TypeTypeConstructor (Annotation.None <$ x)
  TypeTypeOperator x -> TypeTypeOperator (Annotation.None <$ x)
  TypeVariable x -> TypeVariable x
  TypeWildcard x -> TypeWildcard x

fromPureScript ::
  ( Members
    '[ Error InferredConstraintData
     , Error InferredForallWithSkolem
     , Error InferredSkolem
     , Error InferredType
     , Error InfixTypeNotTypeOp
     , Error PrettyPrintForAll
     , Error PrettyPrintFunction
     , Error PrettyPrintObject
     , Error Kind.InferredKind
     , Error Name.Missing
     ]
    e
  ) =>
  Language.PureScript.Type ->
  Eff e (Type Annotation.Unannotated)
fromPureScript = \case
  Language.PureScript.TUnknown _ -> throwError InferredType
  Language.PureScript.TypeVar x -> pure (TypeVariable $ Variable x)
  Language.PureScript.TypeLevelString x -> pure (TypeSymbol $ Symbol x)
  Language.PureScript.TypeWildcard _ -> pure (TypeWildcard Wildcard)
  Language.PureScript.TypeConstructor x ->
    fmap TypeTypeConstructor (Name.qualified (pure . Name.typeConstructor) x)
  Language.PureScript.TypeOp x ->
    fmap TypeTypeOperator (Name.qualified (pure . Name.typeOperator) x)
  Language.PureScript.TypeApp x y -> TypeApplication <$> fromPureScript x <*> fromPureScript y
  Language.PureScript.ForAll x y Nothing ->
    fmap (TypeForall $ Forall $ pure $ Variable x) (fromPureScript y)
  Language.PureScript.ForAll x y (Just z) ->
    throwError (InferredForallWithSkolem x y z)
  Language.PureScript.ConstrainedType x y ->
    TypeConstrained <$> constraint x <*> fromPureScript y
  Language.PureScript.Skolem w x y z -> throwError (InferredSkolem w x y z)
  Language.PureScript.REmpty -> pure (TypeRow $ Row RowParens List.Empty Rowsed)
  Language.PureScript.RCons x y z -> do
    (pairs, rowpen) <- row x y z
    pure (TypeRow $ Row RowParens (List.NonEmpty pairs) rowpen)
  Language.PureScript.KindedType x y ->
    TypeKinded <$> fromPureScript x <*> Kind.fromPureScript y
  Language.PureScript.PrettyPrintFunction x y ->
    throwError (PrettyPrintFunction x y)
  Language.PureScript.PrettyPrintObject x -> throwError (PrettyPrintObject x)
  Language.PureScript.PrettyPrintForAll x y -> throwError (PrettyPrintForAll x y)
  Language.PureScript.BinaryNoParensType (Language.PureScript.TypeOp x') y' z' -> do
    x <- Name.qualified (pure . Name.typeOperator) x'
    y <- fromPureScript y'
    z <- fromPureScript z'
    pure (TypeInfixOperator y x z)
  Language.PureScript.BinaryNoParensType x y z ->
    throwError (InfixTypeNotTypeOp x y z)
  Language.PureScript.ParensInType x -> fmap TypeParens (fromPureScript x)

newtype Variable
  = Variable Text
  deriving (Show)

docFromVariable :: Variable -> Doc a
docFromVariable = \case
  Variable x -> pretty x

newtype Variables a
  = Variables (List.List (Variable, Maybe (Kind.Kind a)))
  deriving (Functor, Show)

docFromVariables :: Variables Annotation.Normalized -> Doc b
docFromVariables = \case
  Variables List.Empty -> mempty
  Variables (List.NonEmpty x) -> space <> intercalateMap1 space go x
    where
    go = \case
      (variable, Nothing) -> docFromVariable variable
      (variable, Just kind') -> parens doc'
        where
        doc' =
          docFromVariable variable
            <+> colon
            <> colon
            <+> Variations.singleLine (Kind.doc kind')

normalizeVariables :: Variables a -> Variables Annotation.Normalized
normalizeVariables = \case
  Variables x -> Variables ((fmap . fmap . fmap) Kind.normalize x)

variables ::
  ( Members
    '[ Error Kind.InferredKind
     , Error Name.Missing
     ]
    e
  ) =>
  [(Text, Maybe Language.PureScript.Kind)] ->
  Eff e (Variables Annotation.Unannotated)
variables x =
  fmap
    (Variables . fromList)
    (traverse (bitraverse (pure . Variable) (traverse Kind.fromPureScript)) x)

data Wildcard
  = Wildcard
  deriving (Show)

docFromWildcard :: Wildcard -> Doc a
docFromWildcard = \case
  Wildcard -> "_"

-- Errors

type Errors
  = '[ Error InferredConstraintData
     , Error InferredForallWithSkolem
     , Error InferredSkolem
     , Error InferredType
     , Error InfixTypeNotTypeOp
     , Error PrettyPrintForAll
     , Error PrettyPrintFunction
     , Error PrettyPrintObject
     ]

data InferredConstraintData
  = InferredConstraintData
      !( Language.PureScript.Qualified
           (Language.PureScript.ProperName 'Language.PureScript.ClassName)
       )
      ![Language.PureScript.Type]
      !Language.PureScript.ConstraintData

data InferredForallWithSkolem
  = InferredForallWithSkolem
      !Text
      !Language.PureScript.Type
      !Language.PureScript.SkolemScope

data InferredSkolem
  = InferredSkolem
      !Text
      !Int
      !Language.PureScript.SkolemScope
      !(Maybe Language.PureScript.SourceSpan)

data InferredType
  = InferredType

data InfixTypeNotTypeOp
  = InfixTypeNotTypeOp
      !Language.PureScript.Type
      !Language.PureScript.Type
      !Language.PureScript.Type

data PrettyPrintForAll
  = PrettyPrintForAll ![Text] !Language.PureScript.Type

data PrettyPrintFunction
  = PrettyPrintFunction !Language.PureScript.Type !Language.PureScript.Type

newtype PrettyPrintObject
  = PrettyPrintObject Language.PureScript.Type

instance Display InferredConstraintData where
  display = \case
    InferredConstraintData x y z ->
      "The compiler inferred metadata `"
        <> displayShow z
        <> "` for the constraint `"
        <> displayShow x
        <> " => "
        <> displayShow y
        <> "` There should be no constraint metadata at this point."
        <> " We are either using the wrong function from the PureScript library,"
        <> " or there's a problem in the PureScript library."

instance Display InferredForallWithSkolem where
  display = \case
    InferredForallWithSkolem x y z ->
      "The compiler inferred a skolem `"
        <> displayShow z
        <> "` for the forall `forall "
        <> display x
        <> ". "
        <> displayShow y
        <> "`. There should be no skolems at this point."
        <> " We are either using the wrong function from the PureScript library,"
        <> " or there's a problem in the PureScript library."

instance Display InferredSkolem where
  display = \case
    InferredSkolem w x y z' ->
      "The compiler inferred a skolem `"
        <> display x
        <> "` for the type variable `"
        <> display w
        <> "` with scope `"
        <> displayShow y
        <> foldMap (\z -> "` at `" <> displayShow z) z'
        <> "`. There should be no skolems at this point."
        <> " We are either using the wrong function from the PureScript library,"
        <> " or there's a problem in the PureScript library."

instance Display InferredType where
  display = \case
    InferredType ->
      "The compiler inferred a type."
        <> " But, only types in the source file should exist at this point."
        <> " We are either using the wrong function from the PureScript library,"
        <> " or there's a problem in the PureScript library."

instance Display InfixTypeNotTypeOp where
  display = \case
    InfixTypeNotTypeOp x y z ->
      "We do not handle the case where the infix type is `"
        <> displayShow x
        <> "`. The left side is `"
        <> displayShow y
        <> "`. The right side is `"
        <> displayShow z
        <> "`. If the infix type contains a `TypeOp` somewhere inside of it,"
        <> " we should handle that case appropriately."
        <> " Otherwise, this seems like a problem in the PureScript library."

instance Display PrettyPrintForAll where
  display = \case
    PrettyPrintForAll x' y ->
      "We tried to modify foralls using a function from the PureScript library."
        <> " We ended up with `forall"
        <> foldMap (\x -> " " <> display x) x'
        <> "."
        <> displayShow y
        <> "`. We should handle modifying foralls ourselves."

instance Display PrettyPrintFunction where
  display = \case
    PrettyPrintFunction x y ->
      "We tried to modify function types using a function"
        <> " from the PureScript library."
        <> " We ended up with `"
        <> displayShow x
        <> " -> "
        <> displayShow y
        <> "`. We should handle modifying function types ourselves."

instance Display PrettyPrintObject where
  display = \case
    PrettyPrintObject x ->
      "We tried to modify a record type using a function"
        <> " from the PureScript library."
        <> " We ended up with `"
        <> displayShow x
        <> "`. We should handle modifying record types ourselves."