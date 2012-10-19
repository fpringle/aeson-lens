{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ViewPatterns      #-}

module Data.Aeson.Lens (
  ValueIx(..),
  valueAt,
  arr, obj,
  ) where

import           Control.Applicative
import           Control.Lens
import           Data.Aeson
import qualified Data.HashMap.Strict as HMS
import           Data.Maybe
import           Data.Monoid
import qualified Data.Text           as T
import qualified Data.Vector         as V

-- $setup
-- >>> import Data.Maybe
-- >>> import qualified Data.ByteString.Lazy.Char8 as L
-- >>> import Data.Text ()
-- >>> let v = decode (L.pack "{\"foo\": {\"baz\": 3.14}, \"bar\": [123, false, null]}") :: Maybe Value

data ValueIx = ArrIx Int | ObjIx T.Text

-- | Lens of Value
valueAt :: (ToJSON v, FromJSON v)
           => ValueIx
           -> SimpleIndexedLens ValueIx (Maybe Value) (Maybe v)
valueAt k = index $ \f (fmap toJSON -> v) -> (go k v) <$> f k (lu k v) where
  go (ObjIx ix) (Just (Object o)) Nothing  = Just $ Object $ HMS.delete ix o
  go (ObjIx ix) (Just (Object o)) (Just v) = Just $ Object $ HMS.insert ix (toJSON v) o
  go (ObjIx ix) _                 (Just v) = Just $ Object $ HMS.fromList [(ix, toJSON v)]
  go (ArrIx ix) (Just (Array  a)) Nothing  = Just $ Array $ updateV ix Null a
  go (ArrIx ix) (Just (Array  a)) (Just v) = Just $ Array $ updateV ix (toJSON v) a
  go (ArrIx ix) _                 (Just v) = Just $ Array $ updateV ix (toJSON v) mempty
  go _ v _ = v

  lu (ObjIx ix) (Just (Object o)) = fromJSONMaybe =<< HMS.lookup ix o
  lu (ArrIx ix) (Just (Array a)) | ix >= 0 && ix < V.length a = fromJSONMaybe $ a V.! ix
  lu _ _ = Nothing

updateV :: Int -> Value -> V.Vector Value -> V.Vector Value
updateV i v a
  | i >= V.length a =
    updateV i v $ V.generate (i + 1) $ \ii -> fromMaybe Null $ a `V.indexM` ii
  | otherwise =
    a V.// [(i, v)]

fromJSONMaybe :: FromJSON a => Value -> Maybe a
fromJSONMaybe v = case fromJSON v of
  Error   _ -> Nothing
  Success a -> Just a

-- | Lens of Array
--
-- >>> L.unpack $ encode v
-- "{\"bar\":[123,false,null],\"foo\":{\"baz\":3.14}}"
-- >>> v ^. obj (T.pack "bar") . arr 1 :: Maybe Bool
-- Just False
-- >>> v ^. obj (T.pack "bar") . arr 1 :: Maybe String
-- Nothing
-- >>> v ^. obj (T.pack "bar") . arr 3 :: Maybe Value
-- Nothing
-- >>> v ^. arr 0 :: Maybe Value
-- Nothing
-- >>> let x = arr 0 .~ Just 1 $ Nothing
-- >>> L.unpack $ encode x
-- "[1]"
-- >>> let y = arr 1 .~ Just "hoge" $ x
-- >>> L.unpack $ encode y
-- "[1,\"hoge\"]"
-- >>> let z = arr 0 .~ Just False $ y
-- >>> L.unpack $ encode z
-- "[false,\"hoge\"]"
arr :: (ToJSON v, FromJSON v)
       => Int
       -> SimpleIndexedLens ValueIx (Maybe Value) (Maybe v)
arr = valueAt . ArrIx

-- | Lens of Object
--
-- >>> v ^. obj (T.pack "foo") . obj (T.pack "baz") :: Maybe Double
-- Just 3.14
-- >>> v ^. obj (T.pack "foo") . obj (T.pack "baz") :: Maybe Object
-- Nothing
-- >>> v ^. obj (T.pack "foo") . obj (T.pack "hoge") :: Maybe Value
-- Nothing
-- >>> v ^. obj (T.pack "hoge") :: Maybe Value
-- Nothing
-- >>> let w = obj (T.pack "a") .~ Just 2.23 $ Nothing
-- >>> L.unpack $ encode w
-- "{\"a\":2.23}"
-- >>> let x = obj (T.pack "b") . obj (T.pack "c") .~ Just True $ w
-- >>> L.unpack $ encode x
-- "{\"b\":{\"c\":true},\"a\":2.23}"
obj :: (ToJSON v, FromJSON v)
       => T.Text
       -> SimpleIndexedLens ValueIx (Maybe Value) (Maybe v)
obj = valueAt . ObjIx