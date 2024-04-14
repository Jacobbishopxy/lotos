{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}

-- file: Util.hs
-- author: Jacob Xie
-- date: 2024/04/14 14:23:44 Sunday
-- brief:

module Lotos.Csv.Util
  ( module Lotos.Csv.Util,
  )
where

import Control.Applicative ((<|>))
import Data.Attoparsec.ByteString (Parser)
import qualified Data.Attoparsec.ByteString as A
import Data.Attoparsec.ByteString.Char8 (string)
import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as L
import Data.Functor (($>))
import qualified Data.HashMap.Strict as HM
import qualified Data.Vector as V
import Data.Word (Word8)
import Lotos.Csv.Adt (Header, NamedRecord, Record)

toStrict :: L.ByteString -> B.ByteString
toStrict = B.concat . L.toChunks

-- | Convert a 'Record' to a 'NamedRecord' by attaching column names.
-- The 'Header' and 'Record' must be of the same length.
toNamedRecord :: Header -> Record -> NamedRecord
toNamedRecord hdr v = HM.fromList . V.toList $ V.zip hdr v

-- | Is the CSV data preceded by a header?
data HasHeader
  = -- | The CSV data is preceded by a header
    HasHeader
  | -- | The CSV data is not preceded by a header
    NoHeader

-- | A strict version of 'Data.Functor.<$>' for monads.
(<$!>) :: (Monad m) => (a -> b) -> m a -> m b
f <$!> m = do
  a <- m
  return $! f a
{-# INLINE (<$!>) #-}

infixl 4 <$!>

-- | Is this an empty record (i.e. a blank line)?
blankLine :: V.Vector B.ByteString -> Bool
blankLine v = V.length v == 1 && B.null (V.head v)

-- | A version of 'liftM2' that is strict in the result of its first
-- action.
liftM2' :: (Monad m) => (a -> b -> c) -> m a -> m b -> m c
liftM2' f a b = do
  !x <- a
  f x <$> b
{-# INLINE liftM2' #-}

-- | Match either a single newline character @\'\\n\'@, or a carriage
-- return followed by a newline character @\"\\r\\n\"@, or a single
-- carriage return @\'\\r\'@.
endOfLine :: Parser ()
endOfLine = (A.word8 newline $> ()) <|> (string "\r\n" $> ()) <|> (A.word8 cr $> ())
{-# INLINE endOfLine #-}

doubleQuote, newline, cr :: Word8
doubleQuote = 34
newline = 10
cr = 13
