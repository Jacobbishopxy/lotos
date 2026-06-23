{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module ClientBridge
  ( SubmitRequest (..),
    SubmitResponse (..),
    acceptedResponse,
    ackTimeoutResponse,
    parseSubmitRequestBody,
    requestTooLargeResponse,
    submitErrorResponse,
    submitTaskTomlWith,
    unsupportedFormatResponse,
    validationErrorResponse,
  )
where

import Adt (ClientTask)
import Client (readTaskFromTomlText)
import Control.Exception (SomeException, try)
import Data.Aeson ((.=))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as Text
import Lotos.Zmq (Ack, Task (..))

-- | Browser-facing submit envelope. Operational client/ZMQ config is intentionally absent.
data SubmitRequest = SubmitRequest
  { submitFormat :: Text.Text,
    submitTaskToml :: Text.Text
  }
  deriving (Show, Eq)

-- | Structured bridge response used by both the executable and tests.
data SubmitResponse = SubmitResponse
  { responseOk :: Bool,
    responseStatus :: Text.Text,
    responseMessage :: Text.Text,
    responseTaskName :: Maybe Text.Text
  }
  deriving (Show, Eq)

instance Aeson.ToJSON SubmitResponse where
  toJSON SubmitResponse {..} =
    Aeson.object
      [ "ok" .= responseOk,
        "status" .= responseStatus,
        "message" .= responseMessage,
        "taskName" .= responseTaskName
      ]

validationErrorResponse :: Text.Text -> SubmitResponse
validationErrorResponse message = SubmitResponse False "validation-error" message Nothing

unsupportedFormatResponse :: SubmitResponse
unsupportedFormatResponse = SubmitResponse False "unsupported-format" "unsupported format: only toml is supported" Nothing

requestTooLargeResponse :: Int -> SubmitResponse
requestTooLargeResponse maxBytes =
  validationErrorResponse $
    "request body exceeds bridgeMaxRequestBytes (" <> Text.pack (show maxBytes) <> " bytes)"

ackTimeoutResponse :: Int -> SubmitResponse
ackTimeoutResponse timeoutSec =
  SubmitResponse
    False
    "ack-timeout"
    ("no ACK received before reqTimeoutSec (" <> Text.pack (show timeoutSec) <> "s)")
    Nothing

acceptedResponse :: Text.Text -> SubmitResponse
acceptedResponse taskName = SubmitResponse True "accepted" "accepted/enqueued" (Just taskName)

submitErrorResponse :: SubmitResponse
submitErrorResponse = SubmitResponse False "submit-error" "submission failed before an ACK could be processed" Nothing

parseSubmitRequestBody :: Int -> BL.ByteString -> Either SubmitResponse SubmitRequest
parseSubmitRequestBody maxBytes body
  | BL.length body > fromIntegral maxBytes = Left $ requestTooLargeResponse maxBytes
  | otherwise = do
      value <- case Aeson.eitherDecode body of
        Left err -> Left $ validationErrorResponse $ "invalid JSON submit envelope: " <> Text.pack err
        Right decoded -> Right decoded
      parseSubmitRequestValue value

parseSubmitRequestValue :: Aeson.Value -> Either SubmitResponse SubmitRequest
parseSubmitRequestValue (Aeson.Object object) = do
  let allowedKeys = ["format", "taskToml"] :: [Text.Text]
      presentKeys = Key.toText <$> KeyMap.keys object
      unexpectedKeys = filter (`notElem` allowedKeys) presentKeys
  if null unexpectedKeys
    then pure ()
    else
      Left $
        validationErrorResponse $
          "unsupported request field(s): "
            <> Text.intercalate ", " unexpectedKeys
            <> "; only format and taskToml are accepted"

  format <- fieldText "format" object
  taskToml <- fieldText "taskToml" object
  if Text.toLower format == "toml"
    then pure ()
    else Left unsupportedFormatResponse
  if Text.null taskToml
    then Left $ validationErrorResponse "taskToml is required and must not be empty"
    else Right $ SubmitRequest format taskToml
parseSubmitRequestValue _ = Left $ validationErrorResponse "submit request must be a JSON object"

fieldText :: Text.Text -> KeyMap.KeyMap Aeson.Value -> Either SubmitResponse Text.Text
fieldText fieldName object =
  case KeyMap.lookup (Key.fromText fieldName) object of
    Just (Aeson.String value) -> Right value
    Just _ -> Left $ validationErrorResponse $ fieldName <> " must be a string"
    Nothing -> Left $ validationErrorResponse $ fieldName <> " is required"

submitTaskTomlWith :: (Task ClientTask -> IO (Maybe Ack)) -> Int -> SubmitRequest -> IO SubmitResponse
submitTaskTomlWith submit timeoutSec SubmitRequest {..} =
  case readTaskFromTomlText submitTaskToml of
    Left err -> pure $ validationErrorResponse $ Text.pack err
    Right task -> do
      result <- try (submit task) :: IO (Either SomeException (Maybe Ack))
      case result of
        Left _ -> pure submitErrorResponse
        Right Nothing -> pure $ ackTimeoutResponse timeoutSec
        Right (Just _) -> pure $ acceptedResponse (taskContent task)
