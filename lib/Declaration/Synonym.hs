module Declaration.Synonym where

import "rio" RIO

import "freer-simple" Control.Monad.Freer        (Eff, Members)
import "freer-simple" Control.Monad.Freer.Error  (Error)
import "prettyprinter" Data.Text.Prettyprint.Doc
    ( Doc
    , equals
    , indent
    , line
    , (<+>)
    )

import qualified "purescript" Language.PureScript

import qualified "this" Annotation
import qualified "this" Comment
import qualified "this" Kind
import qualified "this" Name
import qualified "this" Type
import qualified "this" Variations

data Synonym a
  = Synonym !Comment.Comments !(Name.Type a) !(Type.Variables a) !(Type.Type a)
  deriving (Functor, Show)

doc :: Synonym Annotation.Normalized -> Variations.Variations (Doc a)
doc = \case
  Synonym w x y z ->
    Variations.Variations { Variations.multiLine, Variations.singleLine }
      where
      multiLine =
        Comment.docFromComments w
          <> "type" <+> Name.docFromType x <> Type.docFromVariables y
          <> line
          <> indent 2 (equals <+> Variations.multiLine (Type.doc z))
          <> line
      singleLine =
        Comment.docFromComments w
          <> "type" <+> Name.docFromType x <> Type.docFromVariables y
          <> line
          <> indent 2 (equals <+> Variations.singleLine (Type.doc z))
          <> line

normalize :: Synonym a -> Synonym Annotation.Normalized
normalize = \case
  Synonym w x y z ->
    Synonym
      w
      (Annotation.None <$ x)
      (Type.normalizeVariables y)
      (Type.normalize z)

fromPureScript ::
  ( Members
    '[ Error Kind.InferredKind
     , Error Name.Missing
     , Error Type.InferredConstraintData
     , Error Type.InferredForallWithSkolem
     , Error Type.InferredSkolem
     , Error Type.InferredType
     , Error Type.InfixTypeNotTypeOp
     , Error Type.PrettyPrintForAll
     , Error Type.PrettyPrintFunction
     , Error Type.PrettyPrintObject
     ]
    e
  ) =>
  Language.PureScript.SourceAnn ->
  Language.PureScript.ProperName 'Language.PureScript.TypeName ->
  [(Text, Maybe Language.PureScript.Kind)] ->
  Language.PureScript.Type ->
  Eff e (Synonym Annotation.Unannotated)
fromPureScript (_, comments') name' variables' type'' = do
  let comments = Comment.comments comments'
      name = Name.type' name'
  vars <- Type.variables variables'
  type' <- Type.fromPureScript type''
  pure (Synonym comments name vars type')