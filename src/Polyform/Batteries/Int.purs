module Polyform.Batteries.Int where

import Prelude

import Data.Int (fromString) as Int
import Polyform.Batteries (Dual', Validator', error) as Batteries
import Polyform.Dual (dual) as Dual
import Polyform.Validator (liftFnMaybe) as Validator
import Type.Proxy (Proxy(..))
import Type.Row (type (+))

_intExpected = Proxy ∷ Proxy "intExpected"

type IntExpected e = (intExpected ∷ String | e)

validator ∷ ∀ e m. Applicative m ⇒ Batteries.Validator' m (IntExpected + e) String Int
validator = Validator.liftFnMaybe (Batteries.error _intExpected $ append "Expecting a string but got: ") Int.fromString

dual ∷ ∀ e m. Applicative m ⇒ Batteries.Dual' m (IntExpected + e) String Int
dual = Dual.dual validator (pure <<< show)
