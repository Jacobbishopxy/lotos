{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Main where

import Client (defaultClientConfig, submitClientTask)
import ClientBridge
  ( SubmitResponse (..),
    parseSubmitRequestBody,
    requestTooLargeResponse,
    submitTaskTomlWith,
    validationErrorResponse,
  )
import Control.Concurrent.MVar (MVar, newMVar, withMVar)
import Control.Monad (when)
import Data.Aeson ((.:?), (.!=))
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import Data.Char (isControl)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import qualified Data.Text.Encoding.Error as TextEncodingError
import Data.String (fromString)
import Data.Time.Clock (UTCTime, diffUTCTime, getCurrentTime)
import Data.Time.Format.ISO8601 (iso8601Show)
import GHC.Generics (Generic)
import Lotos.Zmq (ClientServiceConfig (..))
import Network.HTTP.Types (Status, methodOptions, methodPost, status200, status204, status400, status403, status404, status405, status413, status500, status504)
import Network.HTTP.Types.Header (ResponseHeaders)
import Network.Wai (Application, Request, Response, getRequestBodyChunk, pathInfo, remoteHost, requestHeaders, requestMethod, responseLBS)
import qualified Network.Wai.Handler.Warp as Warp
import System.Directory (createDirectoryIfMissing)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

-- | Server-owned bridge configuration. The browser never supplies these values.
data ClientBridgeConfig = ClientBridgeConfig
  { bridgeBindHost :: Text.Text,
    bridgePort :: Int,
    bridgeMaxRequestBytes :: Int,
    bridgeAllowedOrigins :: [Text.Text],
    bridgeAllowNoOrigin :: Bool,
    bridgeClient :: ClientServiceConfig
  }
  deriving (Show, Generic)

instance Aeson.FromJSON ClientBridgeConfig where
  parseJSON = Aeson.withObject "ClientBridgeConfig" $ \value ->
    ClientBridgeConfig
      <$> value .:? "bridgeBindHost" .!= bridgeBindHost defaultBridgeConfig
      <*> value .:? "bridgePort" .!= bridgePort defaultBridgeConfig
      <*> value .:? "bridgeMaxRequestBytes" .!= bridgeMaxRequestBytes defaultBridgeConfig
      <*> value .:? "bridgeAllowedOrigins" .!= bridgeAllowedOrigins defaultBridgeConfig
      <*> value .:? "bridgeAllowNoOrigin" .!= bridgeAllowNoOrigin defaultBridgeConfig
      <*> value .:? "bridgeClient" .!= bridgeClient defaultBridgeConfig

defaultBridgeConfig :: ClientBridgeConfig
defaultBridgeConfig =
  ClientBridgeConfig
    { bridgeBindHost = "127.0.0.1",
      bridgePort = 8090,
      bridgeMaxRequestBytes = 65536,
      bridgeAllowedOrigins = defaultAllowedBrowserOrigins,
      bridgeAllowNoOrigin = True,
      bridgeClient = defaultClientConfig
    }

usage :: String
usage =
  unlines
    [ "Usage:",
      "  ts-client-bridge",
      "  ts-client-bridge CLIENT_BRIDGE_CONFIG_JSON",
      "",
      "The bridge listens on bridgeBindHost:bridgePort and accepts only POST /submit",
      "with JSON {\"format\":\"toml\",\"taskToml\":\"...\"}. Client/ZMQ config is",
      "loaded server-side from the bridge config and is never accepted from the browser."
    ]

loadBridgeConfig :: [String] -> IO ClientBridgeConfig
loadBridgeConfig [] = pure defaultBridgeConfig
loadBridgeConfig [path] = do
  decoded <- Aeson.eitherDecodeFileStrict path
  case decoded of
    Left err -> dieWith $ "invalid bridge config " <> path <> ": " <> err
    Right cfg -> pure cfg
loadBridgeConfig _ = dieWith usage

validateBridgeConfig :: ClientBridgeConfig -> IO ()
validateBridgeConfig ClientBridgeConfig {..} = do
  when (Text.null bridgeBindHost) $ dieWith "bridgeBindHost must not be empty"
  when (bridgePort <= 0 || bridgePort > 65535) $ dieWith "bridgePort must be between 1 and 65535"
  when (bridgeMaxRequestBytes <= 0) $ dieWith "bridgeMaxRequestBytes must be positive"

dieWith :: String -> IO a
dieWith msg = do
  hPutStrLn stderr msg
  exitFailure

defaultAllowedBrowserOrigins :: [Text.Text]
defaultAllowedBrowserOrigins =
  [ "http://127.0.0.1:5173",
    "http://localhost:5173",
    "http://127.0.0.1:4173",
    "http://localhost:4173"
  ]

originHeader :: Request -> Maybe BS.ByteString
originHeader req = lookup "Origin" (requestHeaders req)

decodeOrigin :: BS.ByteString -> Text.Text
decodeOrigin = TextEncoding.decodeUtf8With TextEncodingError.lenientDecode

originAllowed :: ClientBridgeConfig -> Request -> Bool
originAllowed ClientBridgeConfig {..} req =
  case originHeader req of
    Nothing -> bridgeAllowNoOrigin
    Just origin -> decodeOrigin origin `elem` bridgeAllowedOrigins

jsonHeadersFor :: ClientBridgeConfig -> Request -> ResponseHeaders
jsonHeadersFor bridgeConfig req =
  ("Content-Type", "application/json") : corsHeaders
  where
    corsHeaders =
      case originHeader req of
        Just origin | originAllowed bridgeConfig req ->
          [ ("Access-Control-Allow-Origin", origin),
            ("Vary", "Origin"),
            ("Access-Control-Allow-Headers", "Content-Type, Accept"),
            ("Access-Control-Allow-Methods", "POST, OPTIONS")
          ]
        _ -> []

sendJsonStatus :: ClientBridgeConfig -> Request -> Status -> SubmitResponse -> (Response -> IO b) -> IO b
sendJsonStatus bridgeConfig req httpStatus response respond = respond $ responseLBS httpStatus (jsonHeadersFor bridgeConfig req) (Aeson.encode response)

httpStatusFor :: SubmitResponse -> Status
httpStatusFor SubmitResponse {responseOk = True} = status200
httpStatusFor SubmitResponse {responseStatus = "ack-timeout"} = status504
httpStatusFor SubmitResponse {responseStatus = "submit-error"} = status500
httpStatusFor _ = status400

readLimitedBody :: Int -> Request -> IO (Either SubmitResponse BL.ByteString)
readLimitedBody maxBytes req = go 0 []
  where
    go total chunks = do
      chunk <- getRequestBodyChunk req
      if BS.null chunk
        then pure $ Right $ BL.fromChunks $ reverse chunks
        else do
          let total' = total + BS.length chunk
          if total' > maxBytes
            then pure $ Left $ requestTooLargeResponse maxBytes
            else go total' (chunk : chunks)

sanitizeAuditText :: Text.Text -> String
sanitizeAuditText = Text.unpack . Text.map replaceControl
  where
    replaceControl character
      | isControl character = ' '
      | otherwise = character

appendAuditLog :: Request -> Int -> UTCTime -> SubmitResponse -> IO ()
appendAuditLog req bodyBytes startedAt response = do
  finishedAt <- getCurrentTime
  createDirectoryIfMissing True "logs"
  let latencyMs :: Integer
      latencyMs = round (diffUTCTime finishedAt startedAt * 1000)
      taskName = maybe "-" sanitizeAuditText (responseTaskName response)
      line =
        mconcat
          [ iso8601Show finishedAt,
            " remote=",
            show (remoteHost req),
            " method=POST path=/submit bytes=",
            show bodyBytes,
            " status=",
            Text.unpack (responseStatus response),
            " ok=",
            show (responseOk response),
            " taskName=",
            taskName,
            " latencyMs=",
            show latencyMs,
            "\n"
          ]
  appendFile "./logs/taskScheduleClientBridge.log" line

handleSubmit :: ClientBridgeConfig -> MVar () -> Application
handleSubmit bridgeConfig@ClientBridgeConfig {..} submitLock req respond = do
  startedAt <- getCurrentTime
  bodyResult <- readLimitedBody bridgeMaxRequestBytes req
  response <- case bodyResult of
    Left tooLarge -> pure tooLarge
    Right body ->
      case parseSubmitRequestBody bridgeMaxRequestBytes body of
        Left validation -> pure validation
        Right submitRequest ->
          withMVar submitLock $ \() ->
            submitTaskTomlWith (submitClientTask bridgeClient) (reqTimeoutSec bridgeClient) submitRequest
  appendAuditLog req (either (const (bridgeMaxRequestBytes + 1)) (fromIntegral . BL.length) bodyResult) startedAt response
  let httpStatus =
        case bodyResult of
          Left _ -> status413
          Right _ -> httpStatusFor response
  respond $ responseLBS httpStatus (jsonHeadersFor bridgeConfig req) (Aeson.encode response)

sendRejectedOrigin :: ClientBridgeConfig -> Request -> (Response -> IO b) -> IO b
sendRejectedOrigin cfg req respond = do
  let response = validationErrorResponse "browser origin is not allowed for /submit"
  when (requestMethod req == methodPost) $ do
    startedAt <- getCurrentTime
    appendAuditLog req 0 startedAt response
  sendJsonStatus cfg req status403 response respond

bridgeApp :: ClientBridgeConfig -> MVar () -> Application
bridgeApp cfg submitLock req respond
  | pathInfo req == ["submit"] && not (originAllowed cfg req) =
      sendRejectedOrigin cfg req respond
  | pathInfo req == ["submit"] && requestMethod req == methodOptions =
      respond $ responseLBS status204 (jsonHeadersFor cfg req) ""
  | pathInfo req == ["submit"] && requestMethod req == methodPost =
      handleSubmit cfg submitLock req respond
  | pathInfo req == ["submit"] =
      sendJsonStatus cfg req status405 (validationErrorResponse "POST is required for /submit") respond
  | otherwise =
      sendJsonStatus cfg req status404 (validationErrorResponse "not found") respond

main :: IO ()
main = do
  cfg@ClientBridgeConfig {..} <- loadBridgeConfig =<< getArgs
  validateBridgeConfig cfg
  submitLock <- newMVar ()
  putStrLn $
    "ts-client-bridge listening on http://"
      <> Text.unpack bridgeBindHost
      <> ":"
      <> show bridgePort
      <> "/submit; frontend="
      <> Text.unpack (loadBalancerFrontendAddr bridgeClient)
      <> "; reqTimeoutSec="
      <> show (reqTimeoutSec bridgeClient)
      <> "; maxRequestBytes="
      <> show bridgeMaxRequestBytes
  let settings =
        Warp.setHost (fromString $ Text.unpack bridgeBindHost) $
          Warp.setPort bridgePort Warp.defaultSettings
  Warp.runSettings settings (bridgeApp cfg submitLock)
