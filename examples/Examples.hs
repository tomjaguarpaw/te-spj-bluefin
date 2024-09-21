{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -Wall #-}

module Examples where

import Bluefin.Compound (useImplIn)
import Bluefin.EarlyReturn (EarlyReturn, returnEarly, withEarlyReturn)
import Bluefin.Eff (Eff, Effects, bracket, runEff, runPureEff, (:&), (:>))
import Bluefin.Exception (Exception, catch, throw)
import Bluefin.IO (IOE, effIO)
import Bluefin.State (evalState, get, put)
import Control.Monad (when)
import Data.Foldable (for_)
import Data.Traversable (for)
import System.IO (Handle, IOMode, hClose, openFile)

newtype WrappedHandle (e :: Effects)
  = -- Constructor hidden from clients
    MkWrappedHandle Handle

-- Basically the same as withFile
--
-- https://www.stackage.org/haddock/lts-22.34/base-4.18.2.1/System-IO.html#v:withFile
withHandle ::
  (e :> es) =>
  IOE e ->
  FilePath ->
  IOMode ->
  (forall e1. WrappedHandle e1 -> Eff (e1 :& es) b) ->
  Eff es b
withHandle io fp mode f =
  bracket
    (effIO io (openFile fp mode))
    (\h -> effIO io (hClose h))
    (useImplIn (f . MkWrappedHandle))

-- This correctly fails to type check, preventing us from using the
-- file after it has been closed.
--
-- bad :: e :> es => IOE e -> Eff es (WrappedHandle e1)
-- bad io = withHandle io "/dev/null" WriteMode pure

find :: [a] -> (a -> Bool) -> Maybe a
find l cond = runPureEff $ withEarlyReturn $ \early -> do
  for_ l $ \a -> do
    when (cond a) $
      returnEarly early (Just a)

  pure Nothing

printCumSum :: [Int] -> IO ()
printCumSum l = runEff $ \io -> evalState 0 $ \soFar -> do
  for_ l $ \i -> do
    soFar' <- get soFar
    let next = soFar' + i
    put soFar next
    effIO io (print next)

allOK :: (e :> es) => EarlyReturn (Maybe a) e -> [Maybe a] -> Eff es [a]
allOK early l =
  for l $ \case
    Nothing -> returnEarly early Nothing
    Just i -> pure i

canThrowF :: (e :> es) => Exception () e -> Int -> Eff es Int
canThrowF ex x = do
  let limit = 10
  if x < limit then pure (x * x) else throw ex ()

canThrowXs :: [Int] -> Int
canThrowXs xs =
  runPureEff $
    catch
      (\ex -> sum <$> traverse (canThrowF ex) xs)
      (\() -> pure (-1))
