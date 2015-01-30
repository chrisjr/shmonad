{-# LANGUAGE GADTs #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ExtendedDefaultRules #-}

module Control.Monad.Shmonad.Statement where

import System.Posix (Fd)
-- import System.Posix.IO (stdInput, stdOutput, stdError)
import Control.Monad.Free
import Control.Monad.RWS.Lazy
import Control.Monad.Shmonad.Expression
import qualified Data.Text.Lazy as L
import Data.Number.Nat

default (L.Text)

data Redirect
  = FdToFile Path
  | FdToFd Fd Fd
  | StdinFromFile Path

data Cmd = Cmd
  { program :: Expr Path
  , args :: [Expr Str]
  , redirs :: [Redirect]
  }

-- | Provides a writer and state monad for transforming ASTs into shell script.
type Transpiler = RWS () Str Nat

data Statement next where
  NewVar :: (Variable v) => Name -> Expr v -> (VarID v -> next) -> Statement next
  SetVar :: (Variable v) => VarID v -> Expr v -> next -> Statement next
  Echo :: Expr Str -> next -> Statement next
  Exit :: Expr Integer -> next -> Statement next

instance Functor Statement where
  fmap f (NewVar name' expr' cont) = NewVar name' expr' (f . cont)
  fmap f (SetVar v e n) = SetVar v e (f n)
  fmap f (Echo str n) = Echo str (f n)
  fmap f (Exit e n) = Exit e (f n)

type Script = Free Statement

transpile :: Script a -> Transpiler ()
transpile s = case s of
  Free f -> case f of
    NewVar name' expr' cont -> do
      n <- get
      let vi = VarID n name' :: VarID v
      put (n + 1)
      tell $ fromName (uniqueName vi) <> "=" <> shExpr expr' <> "\n"
      transpile (cont vi)
    SetVar v e n -> do
      tell $ fromName (uniqueName v) <> "=" <> shExpr e <> "\n"
      transpile n
    Echo str n -> do
      tell $ "echo " <> shExpr str <> "\n"
      transpile n
    Exit e n -> do
      tell $ "exit " <> shExpr e <> "\n"
      transpile n
  Pure _ -> return ()