{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}

-- file: Csv.hs
-- author: Jacob Xie
-- date: 2024/04/07 22:18:31 Sunday
-- brief:

module Lotos.Csv
  ( FromRecord (..),
    Parser (..),
    readCsvRaw,
    readCsv,
    (~>),
  )
where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BSL
import qualified Data.HashMap.Strict as HM
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Read as TR
import qualified Data.Vector as V
import GHC.Float (double2Float)
import qualified HaskellWorks.Data.Dsv.Lazy.Cursor as SVL
import qualified HaskellWorks.Data.Dsv.Lazy.Cursor.Lazy as SVL
import Lotos.Util

----------------------------------------------------------------------------------------------------
-- Type
----------------------------------------------------------------------------------------------------

type RawRow = V.Vector BSL.ByteString

type RawResult = V.Vector RawRow

----------------------------------------------------------------------------------------------------
-- Class
----------------------------------------------------------------------------------------------------

-- Typeclass for parsing a single record
class FromRecord a where
  parseRecord :: HM.HashMap BSL.ByteString Int -> RawRow -> Either String a

class Parser a where
  parse :: BSL.ByteString -> a

----------------------------------------------------------------------------------------------------
-- Private Fn
----------------------------------------------------------------------------------------------------

-- Get indices for fields from the first record
getFieldIndices :: RawRow -> HM.HashMap BSL.ByteString Int
getFieldIndices = V.ifoldl' (\acc i bs -> HM.insert bs i acc) HM.empty

instance Parser String where
  parse = T.unpack . TE.decodeUtf8Lenient . BS.toStrict

instance Parser (Maybe String) where
  parse s = case f s of
    "" -> Nothing
    s' -> Just s'
    where
      f = T.unpack . TE.decodeUtf8Lenient . BS.toStrict

instance Parser Int where
  parse s = case TR.decimal . TE.decodeUtf8Lenient $ BS.toStrict s of
    Right (i, r) | r == T.empty -> i
    _ -> 0

instance Parser (Maybe Int) where
  parse s = case TR.decimal . TE.decodeUtf8Lenient $ BS.toStrict s of
    Right (i, r) | r == T.empty -> Just i
    _ -> Nothing

instance Parser Float where
  parse s = case TR.double . TE.decodeUtf8Lenient $ BS.toStrict s of
    Right (i, r) | r == T.empty -> double2Float i
    _ -> 0

instance Parser (Maybe Float) where
  parse s = case TR.double . TE.decodeUtf8Lenient $ BS.toStrict s of
    Right (i, r) | r == T.empty -> Just $ double2Float i
    _ -> Nothing

instance Parser Double where
  parse s = case TR.double . TE.decodeUtf8Lenient $ BS.toStrict s of
    Right (i, r) | r == T.empty -> i
    _ -> 0

instance Parser (Maybe Double) where
  parse s = case TR.double . TE.decodeUtf8Lenient $ BS.toStrict s of
    Right (i, r) | r == T.empty -> Just i
    _ -> Nothing

instance Parser Bool where
  parse s = case T.toLower $ f s of
    "true" -> True
    _ -> False
    where
      f = TE.decodeUtf8Lenient . BS.toStrict

instance Parser (Maybe Bool) where
  parse s = case T.toLower $ f s of
    "true" -> Just True
    "false" -> Just False
    _ -> Nothing
    where
      f = TE.decodeUtf8Lenient . BS.toStrict

----------------------------------------------------------------------------------------------------
-- Public Fn
----------------------------------------------------------------------------------------------------

(~>) :: (Parser a) => (HM.HashMap BSL.ByteString Int, BSL.ByteString) -> RawRow -> Either String a
(~>) (fieldIndices, field) vec = do
  idx <- maybe2Either "field not found" $ HM.lookup field fieldIndices
  return $ parse $ vec V.! idx

-- Define a function to parse a CSV file into a vector of vectors of ByteString
readCsvRaw :: FilePath -> IO RawResult
readCsvRaw f = do
  bs <- BSL.readFile f
  let c = SVL.makeCursor (toEnum . fromEnum $ ',') bs
  return $ SVL.toVectorVector c

readCsv :: (FromRecord a) => FilePath -> IO (Either String (V.Vector a))
readCsv f = do
  raw <- readCsvRaw f
  let header = V.head raw
      fieldIndices = getFieldIndices header
      records = V.tail raw

  return $ traverse (parseRecord fieldIndices) records
