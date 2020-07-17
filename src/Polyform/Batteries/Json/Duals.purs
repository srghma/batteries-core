module Polyform.Batteries.Json.Duals where

import Prelude

import Data.Argonaut (Json, jsonNull)
import Data.Argonaut (fromArray, fromBoolean, fromNumber, fromObject, fromString) as Argonaut
import Data.Argonaut.Decode.Class (class DecodeJson)
import Data.Argonaut.Encode.Class (class EncodeJson, encodeJson)
import Data.Either (note)
import Data.Generic.Rep (class Generic, NoArguments)
import Data.Int (toNumber) as Int
import Data.Maybe (Maybe)
import Data.Newtype (un)
import Data.Profunctor (lcmap)
import Data.Profunctor.Choice ((|||))
import Data.Profunctor.Star (Star(..))
import Data.Semigroup.First (First(..))
import Data.Traversable (traverse)
import Data.Validation.Semigroup (invalid)
import Data.Variant (Variant)
import Foreign.Object (Object) as Foreign
import Foreign.Object (singleton) as Object
import Polyform.Batteries (Dual) as Batteries
import Polyform.Batteries.Json.Validators (ArgonautError, ArrayExpected, BooleanExpected, Errors, JNull, NullExpected, NumberExpected, ObjectExpected, StringExpected, FieldMissing)
import Polyform.Batteries.Json.Validators (Errors, argonaut, array, arrayOf, boolean, error, field, fromNull, int, liftValidator, null, number, object, optionalField, string) as Json.Validators
import Polyform.Dual (Dual(..), DualD(..), hoistParser) as Dual
import Polyform.Dual (dual, (~))
import Polyform.Dual.Generic.Sum (class GDualSum)
import Polyform.Dual.Generic.Sum (noArgs', unit') as Dual.Generic.Sum
import Polyform.Dual.Generic.Variant (class GDualVariant)
import Polyform.Dual.Record (Builder, insert) as Dual.Record
import Polyform.Dual.Variant (on) as Dual.Variant
import Polyform.Type.Row (class Cons') as Row
import Polyform.Validator (Validator, liftFn, liftFnV) as Validator
import Polyform.Validator.Dual as Validator.Dual
import Polyform.Validator.Dual.Generic (sum, variant) as Validator.Dual.Generic
import Prim.Row (class Cons) as Row
import Prim.RowList (class RowToList)
import Type.Prelude (class IsSymbol, SProxy(..), reflectSymbol)
import Type.Row (type (+))

type Dual m errs a b = Validator.Dual.Dual m (Errors errs) a b

-- | Please check `Json.Validator.fromValidator`
fromDual
  ∷ ∀ errs i m o. Monad m
  ⇒ Batteries.Dual m errs i o
  → Dual m errs i o
fromDual = Dual.hoistParser Json.Validators.liftValidator

-- | We want to have Monoid for `Object` so we
-- | can compose serializations by monoidal
-- | `append`.
-- | Because `Foreign.Object` has monoid instance
-- | which performs underlining `append` on values
-- | we have to wrap it up and provide appropriate
-- | wrapping with `First`.
type Object a = Foreign.Object (First a)

object
  ∷ ∀ errs m
  . Monad m
  ⇒ Dual m (objectExpected ∷ Json | errs) Json (Object Json)
object = dual
  (map First <$> Json.Validators.object)
  (pure <<< Argonaut.fromObject <<< map runFirst)
  where
    runFirst (First a) = a

-- | This `First` wrapper is necessary because `Object` provides
-- | `Semigroup` instance which based on value `Semigroup`.
-- | We use just left bias union here.
field
  ∷ ∀ a e m
  . Monad m
  ⇒ String
  → Dual m (FieldMissing + e) Json a
  → Dual m (FieldMissing + e) (Object Json) a
field label d =
  dual prs ser
  where
    Dual.DualD fieldPrs fieldSer = un Dual.Dual d
    prs = lcmap
      (map (un First))
      (Json.Validators.field label fieldPrs)

    ser = map (Object.singleton label <<< First) <<< fieldSer

optionalField
  ∷ ∀ a err m
  . Monad m
  ⇒ String
  → Dual m err Json a
  → Dual m err (Object Json) (Maybe a)
optionalField label d =
  dual prs ser
  where
    Dual.DualD fieldPrs fieldSer = un Dual.Dual d
    prs = lcmap
      -- | Should we use unsafeCoerce here
      (map (un First))
      (Json.Validators.optionalField label fieldPrs)

    vSer ∷ Maybe a → m Json
    vSer = un Star $ (Star pure ||| Star fieldSer) <<< Star (pure <<< note jsonNull)

    ser = pure <<< (Object.singleton label <<< First) <=< vSer

null
  ∷ ∀ errs m
  . Monad m
  ⇒ Dual m (NullExpected + errs) Json JNull
null = dual
  Json.Validators.null
  (pure <<< Json.Validators.fromNull)

array
  ∷ ∀ errs m
  . Monad m
  ⇒ Dual m (ArrayExpected + errs) Json (Array Json)
array = dual
  Json.Validators.array
  (pure <<< Argonaut.fromArray)

arrayOf
  ∷ ∀ e o m
  . Monad m
  ⇒ Dual m (ArrayExpected + e) Json o
  → Dual m (ArrayExpected + e) Json (Array o)
arrayOf (Dual.Dual (Dual.DualD prs ser)) =
  dual (Json.Validators.arrayOf prs) (map Argonaut.fromArray <<< traverse ser)

int
  ∷ ∀ errs m
  . Monad m
  ⇒ Dual m (intExpected ∷ Json | errs) Json Int
int = dual
  Json.Validators.int
  (pure <<< Argonaut.fromNumber <<< Int.toNumber)

boolean
  ∷ ∀ errs m
  . Monad m
  ⇒ Dual m (BooleanExpected + errs) Json Boolean
boolean = dual
  Json.Validators.boolean
  (pure <<< Argonaut.fromBoolean)

number
  ∷ ∀ errs m
  . Monad m
  ⇒ Dual m (NumberExpected + errs) Json Number
number = dual
  Json.Validators.number
  (pure <<< Argonaut.fromNumber)

string
  ∷ ∀ errs m
  . Monad m
  ⇒ Dual m (StringExpected + errs) Json String
string = dual
  Json.Validators.string
  (pure <<< Argonaut.fromString)

insert ∷ ∀ e l o m prs prs' ser ser'
  . Row.Cons' l o ser ser'
  ⇒ Row.Cons' l o prs prs'
  ⇒ IsSymbol l
  ⇒ Monad m
  ⇒ SProxy l
  → Dual m (FieldMissing + e) Json o
  → Dual.Record.Builder
    (Validator.Validator m (Json.Validators.Errors (FieldMissing + e)))
    m
    (Object Json)
    { | ser'}
    { | prs}
    { | prs'}
insert label dual =
  Dual.Record.insert label (field (reflectSymbol label) dual)

infix 10 insert as :=

insertOptional ∷ ∀ e m l o prs prs' ser ser'
  . Row.Cons' l (Maybe o) ser ser'
  ⇒ Row.Cons' l (Maybe o) prs prs'
  ⇒ IsSymbol l
  ⇒ Monad m
  ⇒ SProxy l
  → Dual m e Json o
  → Dual.Record.Builder
    (Validator.Validator m (Json.Validators.Errors e))
    m
    (Object Json)
    { | ser'}
    { | prs}
    { | prs'}
insertOptional label dual =
  Dual.Record.insert label (optionalField (reflectSymbol label) dual)

infix 10 insertOptional as :=?

insertConst ∷ ∀ e l o m prs prs' ser ser'
  . Row.Cons' l o ser ser'
  ⇒ Row.Cons' l o prs prs'
  ⇒ IsSymbol l
  ⇒ Monad m
  ⇒ SProxy l
  → o
  → Dual.Record.Builder
    (Validator.Validator m (Json.Validators.Errors (FieldMissing + e)))
    m
    (Object Json)
    { | ser'}
    { | prs}
    { | prs'}
insertConst label a = label := (dual prs ser)
  where
    ser = const $ pure jsonNull
    prs = Validator.liftFn (const a)

type CoproductErrors e = (IncorrectTag + StringExpected + FieldMissing + ObjectExpected + e)

variant
  ∷ ∀ e d dl m v
  . Monad m
  ⇒ RowToList d dl
  ⇒ GDualVariant (Validator.Validator m (Json.Validators.Errors (CoproductErrors + e))) m Json dl d v
  ⇒ { | d }
  → Dual m (CoproductErrors + e) Json (Variant v)
variant = Validator.Dual.Generic.variant tagged

sum ∷ ∀ a m e rep r
  . Monad m
  ⇒ Generic a rep
  ⇒ GDualSum (Validator.Validator m (Json.Validators.Errors (CoproductErrors + e))) m Json rep r
  ⇒ { | r }
  → Dual m (CoproductErrors + e) Json a
sum = Validator.Dual.Generic.sum tagged

_incorrectTag = SProxy ∷ SProxy "incorrectTag"

type IncorrectTag e = (incorrectTag ∷ String | e)

tagged
  ∷ ∀ a e l m
  . Monad m
  ⇒ IsSymbol l
  ⇒ SProxy l
  → Dual m (CoproductErrors + e) Json a
  → Dual m (CoproductErrors + e) Json a
tagged label (Dual.Dual (Dual.DualD prs ser))  =
  object >>> tagFields >>> tagged'
  where
    tagFields = Dual.Dual $ { t: _, v: _ }
      <$> _.t ~ field "tag" string
      <*> _.v ~ field "value" identity

    tagged' =
      let
        fieldName = reflectSymbol label
        ser' = map { t: fieldName, v: _ } <<< ser
        prs' = prs <<< Validator.liftFnV \{ t, v } → if fieldName /= t
          then invalid $ Json.Validators.error _incorrectTag t
          else pure v
      in
        dual prs' ser'

on
  ∷ ∀ a l e m r r'
  . Monad m
  ⇒ Row.Cons l a r r'
  ⇒ IsSymbol l
  ⇒ SProxy l
  → Dual m (CoproductErrors + e) Json a
  → Dual m (CoproductErrors + e) Json (Variant r)
  → Dual m (CoproductErrors + e) Json (Variant r')
on label d rest = Dual.Variant.on tagged label d rest

infix 10 on as :>

noArgs ∷ ∀ e m. Monad m ⇒ Dual m e Json NoArguments
noArgs = Dual.Generic.Sum.noArgs' jsonNull

unit ∷ ∀ e m. Monad m ⇒ Dual m e Json Unit
unit = Dual.Generic.Sum.unit' jsonNull

argonaut ∷ ∀ a e m. Monad m ⇒ EncodeJson a ⇒ DecodeJson a ⇒ Dual m (ArgonautError + e) Json a
argonaut = dual Json.Validators.argonaut ser
  where
    ser = (pure <<< encodeJson)

-- decode ∷ ∀ a e. JsonDual Identity Identity e a → Json → Either (Validators.Errors (JsonError + e)) a
-- decode dual j =
--   unwrap $ unwrap (Validator.Dual.runValidator dual j)
-- 
-- encode ∷ ∀ a e. JsonDual Identity Identity e a → a → Json
-- encode dual = un Identity <<< Validator.Dual.runSerializer dual
-- 
