-- file: Logger.hs
-- author: Jacob Xie
-- date: 2024/09/18 09:39:27 Wednesday
-- brief:

module Lotos.Logger
  ( LotosLogger,
    LogLevel (..),
    LotosAppMonad,
    createLogger,
    logDebugM,
    logInfoM,
    logWarnM,
    logErrorM,
    logDebugR,
    logInfoR,
    logWarnR,
    logErrorR,

    -- * unwrap
    logUnwrap,
  )
where

import Control.Exception (Exception, throwIO)
import Control.Monad (when)
import Control.Monad.Reader
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.Time.LocalTime (getZonedTime)
import System.IO

data LogLevel = L_DEBUG | L_INFO | L_WARN | L_ERROR deriving (Eq, Ord, Show, Enum)

type LotosAppMonad = ReaderT LotosLogger IO

data LotosLogger = LotosLogger
  { logDebug :: String -> IO (),
    logInfo :: String -> IO (),
    logWarn :: String -> IO (),
    logError :: String -> IO ()
  }

createLogger :: LogLevel -> IO LotosLogger
createLogger logLevel = do
  now <- getZonedTime
  let fileName = formatTime defaultTimeLocale "%Y-%m-%d.log" now
  handle <- openFile fileName AppendMode
  hSetBuffering handle LineBuffering
  let debugFunc msg = do
        when (L_DEBUG >= logLevel) $ do
          timestamp <- formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S" <$> getZonedTime
          let output = "[" ++ timestamp ++ "] DEBUG: " ++ msg
          putStrLn output
          hPutStrLn handle output
          hFlush handle
      infoFunc msg = do
        when (L_INFO >= logLevel) $ do
          timestamp <- formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S" <$> getZonedTime
          let output = "[" ++ timestamp ++ "] INFO: " ++ msg
          putStrLn output
          hPutStrLn handle output
          hFlush handle
      warnFunc msg = do
        when (L_WARN >= logLevel) $ do
          timestamp <- formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S" <$> getZonedTime
          let output = "[" ++ timestamp ++ "] WARN: " ++ msg
          putStrLn output
          hPutStrLn handle output
          hFlush handle
      errorFunc msg = do
        when (L_ERROR >= logLevel) $ do
          timestamp <- formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S" <$> getZonedTime
          let output = "[" ++ timestamp ++ "] ERROR: " ++ msg
          hPutStrLn stderr output
          hPutStrLn handle output
          hFlush handle
  return $ LotosLogger debugFunc infoFunc warnFunc errorFunc

-- Helper functions for MonadIO
logDebugM, logInfoM, logWarnM, logErrorM :: (MonadIO m) => LotosLogger -> String -> m ()
logDebugM logger = liftIO . logDebug logger
logInfoM logger = liftIO . logInfo logger
logWarnM logger = liftIO . logWarn logger
logErrorM logger = liftIO . logError logger

-- ReaderT helpers
logDebugR, logInfoR, logWarnR, logErrorR :: String -> LotosAppMonad ()
logDebugR msg = ask >>= \logger -> liftIO $ logDebug logger msg
logInfoR msg = ask >>= \logger -> liftIO $ logInfo logger msg
logWarnR msg = ask >>= \logger -> liftIO $ logWarn logger msg
logErrorR msg = ask >>= \logger -> liftIO $ logError logger msg

logUnwrap ::
  (MonadIO m, MonadReader LotosLogger m, Exception e) =>
  (String -> m ()) -> -- Logger function
  (e -> String) -> -- Error formatter
  IO (Either e a) -> -- IO action
  m a
logUnwrap loggerFn formatErr action = do
  result <- liftIO action
  case result of
    Left err -> do
      loggerFn $ formatErr err
      liftIO $ throwIO err
    Right x -> pure x
