module Declaration.Fixity where

import "rio" RIO

import "freer-simple" Control.Monad.Freer        (Eff, Members)
import "freer-simple" Control.Monad.Freer.Error  (Error, throwError)
import "base" Data.Bifunctor                     (bimap)
import "prettyprinter" Data.Text.Prettyprint.Doc (Doc, line, pretty, (<+>))
import "base" GHC.Natural                        (Natural)

import qualified "purescript" Language.PureScript

import qualified "this" Annotation
import qualified "this" Comment
import qualified "this" Name

data Associativity
  = AssociativityLeft
  | AssociativityNone
  | AssociativityRight
  deriving (Show)


associativity :: Language.PureScript.Fixity -> Associativity
associativity = \case
  Language.PureScript.Fixity assoc _ -> case assoc of
    Language.PureScript.Infixl -> AssociativityLeft
    Language.PureScript.Infix  -> AssociativityNone
    Language.PureScript.Infixr -> AssociativityRight

docFromAssociativity :: Associativity -> Doc a
docFromAssociativity = \case
  AssociativityLeft -> "infixl"
  AssociativityNone -> "infix"
  AssociativityRight -> "infixr"

newtype Precedence
  = Precedence Natural
  deriving (Show)

docFromPrecedence :: Precedence -> Doc a
docFromPrecedence = \case
  Precedence x -> pretty x

precedence ::
  ( Members
    '[ Error NegativePrecedence
     ]
    e
  ) =>
  Language.PureScript.Qualified
    (Either Language.PureScript.Ident (Language.PureScript.ProperName a)) ->
  Language.PureScript.Fixity ->
  Eff e Precedence
precedence name = \case
  Language.PureScript.Fixity _ prec
    | prec < 0 -> throwError (NegativePrecedence name prec)
    | otherwise -> pure (Precedence $ fromInteger prec)

data Type a
  = Type
      !Comment.Comments
      !Associativity
      !Precedence
      !(Name.Qualified Name.Type a)
      !(Name.TypeOperator a)
  deriving (Functor, Show)

docFromType :: Type Annotation.Normalized -> Doc b
docFromType = \case
  Type v w x y z ->
    Comment.docFromComments v
      <> docFromAssociativity w
      <+> docFromPrecedence x
      <+> "type"
      <+> Name.docFromQualified Name.docFromType y
      <+> "as"
      <+> Name.docFromTypeOperator' z
      <> line

normalizeType :: Type a -> Type Annotation.Normalized
normalizeType = \case
  Type v w x y z -> Type v w x (Annotation.None <$ y) (Annotation.None <$ z)

type' ::
  ( Members
    '[ Error NegativePrecedence
     , Error Name.InvalidCommon
     , Error Name.Missing
     ]
    e
  ) =>
  Language.PureScript.SourceAnn ->
  Language.PureScript.TypeFixity ->
  Eff e (Type Annotation.Unannotated)
type' (_, comments') = \case
  Language.PureScript.TypeFixity fixity name' op -> do
    let assoc = associativity fixity
        comments = Comment.comments comments'
        operator = Name.typeOperator op
    prec <- precedence (fmap Right name') fixity
    name <- Name.qualified (pure . Name.type') name'
    pure (Type comments assoc prec name operator)

data Value a
  = ValueConstructor
      !Comment.Comments
      !Associativity
      !Precedence
      !(Name.Qualified Name.Constructor a)
      !(Name.ValueOperator a)
  | ValueValue
      !Comment.Comments
      !Associativity
      !Precedence
      !(Name.Qualified Name.Common a)
      !(Name.ValueOperator a)
  deriving (Functor, Show)

docFromValue :: Value Annotation.Normalized -> Doc b
docFromValue = \case
  ValueConstructor v w x y z ->
    Comment.docFromComments v
      <> docFromAssociativity w
      <+> docFromPrecedence x
      <+> Name.docFromQualified Name.docFromConstructor y
      <+> "as"
      <+> Name.docFromValueOperator' z
      <> line
  ValueValue v w x y z ->
    Comment.docFromComments v
      <> docFromAssociativity w
      <+> docFromPrecedence x
      <+> Name.docFromQualified Name.docFromCommon y
      <+> "as"
      <+> Name.docFromValueOperator' z
      <> line

normalizeValue :: Value a -> Value Annotation.Normalized
normalizeValue = \case
  ValueConstructor v w x y z ->
    ValueConstructor v w x (Annotation.None <$ y) (Annotation.None <$ z)
  ValueValue v w x y z ->
    ValueValue v w x (Annotation.None <$ y) (Annotation.None <$ z)

value ::
  ( Members
    '[ Error NegativePrecedence
     , Error Name.InvalidCommon
     , Error Name.Missing
     ]
    e
  ) =>
  Language.PureScript.SourceAnn ->
  Language.PureScript.ValueFixity ->
  Eff e (Value Annotation.Unannotated)
value (_, comments') = \case
  Language.PureScript.ValueFixity fixity name op -> do
    let assoc = associativity fixity
        comments = Comment.comments comments'
        operator = Name.valueOperator op
    prec <- precedence name fixity
    case bimap (<$ name) (<$ name) (Language.PureScript.disqualify name) of
      Left ident -> do
        common <- Name.qualified Name.common ident
        pure (ValueValue comments assoc prec common operator)
      Right constructor' -> do
        constructor <- Name.qualified (pure . Name.constructor) constructor'
        pure (ValueConstructor comments assoc prec constructor operator)

-- Errors

type Errors
  = '[ Error NegativePrecedence
     ]

data NegativePrecedence
  = forall a.
      NegativePrecedence
        !( Language.PureScript.Qualified
           (Either Language.PureScript.Ident (Language.PureScript.ProperName a))
         )
        !Integer

instance Display NegativePrecedence where
  display = \case
    NegativePrecedence x y ->
      "The precedence for `"
        <> display qualified
        <> "` is the negative value `"
        <> display y
        <> "`, but precedence should be non-negative."
        <> " This is probably a problem in the PureScript library."
      where
      qualified =
        Language.PureScript.showQualified
          (either Language.PureScript.showIdent Language.PureScript.runProperName)
          x