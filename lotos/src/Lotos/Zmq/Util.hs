-- file: Util.hs
-- author: Jacob Xie
-- date: 2025/03/14 17:11:34 Friday
-- brief:

module Lotos.Zmq.Util
  ( textToBS,
    textFromBS,
    intFromBS,
    intToBS,
    uuidToBS,
    uuidFromBS,
    uuidOptToBS,
    uuidOptFromBS,
  )
where

import Data.ByteString qualified as B
import Data.ByteString.Char8 qualified as BC
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.UUID qualified as UUID
import Lotos.Zmq.Error

-- Text <-> ByteString
textToBS :: T.Text -> B.ByteString
textToBS = TE.encodeUtf8

textFromBS :: B.ByteString -> Either ZmqError T.Text
textFromBS bs = case TE.decodeUtf8' bs of
  Left err -> Left (ZmqParsing $ "Text decode error: " <> T.pack (show err))
  Right t -> Right t

-- Int <-> ByteString
intToBS :: Int -> B.ByteString
intToBS = BC.pack . show

intFromBS :: B.ByteString -> Either ZmqError Int
intFromBS bs = case BC.readInt bs of
  Just (i, "") -> Right i
  _ -> Left (ZmqParsing $ "Invalid Int: " <> T.pack (BC.unpack bs))

uuidToBS :: UUID.UUID -> B.ByteString
uuidToBS uuid = BC.pack (UUID.toString uuid)

uuidFromBS :: B.ByteString -> Either ZmqError UUID.UUID
uuidFromBS bs = case UUID.fromString (BC.unpack bs) of
  Just uuid -> Right uuid
  Nothing -> Left $ ZmqParsing "Invalid UUID format"

uuidOptToBS :: Maybe UUID.UUID -> B.ByteString
uuidOptToBS Nothing = B.empty
uuidOptToBS (Just uuid) = uuidToBS uuid

uuidOptFromBS :: B.ByteString -> Either ZmqError (Maybe UUID.UUID)
uuidOptFromBS bs
  | B.null bs = Right Nothing
  | otherwise = case UUID.fromString (BC.unpack bs) of
      Just uuid -> Right (Just uuid)
      Nothing -> Left $ ZmqParsing "Invalid UUID format"
