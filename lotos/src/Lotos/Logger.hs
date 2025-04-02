-- file: Logger.hs
-- author: Jacob Xie
-- date: 2024/09/18 09:39:27 Wednesday
-- brief:

module Lotos.Logger
  ( LogLevel (..),
    LogConfig (..),
    LotosApp (..),
    LotosAppMonad,
    LoggerState,
    runLotosApp,
    runLotosAppWithState,
    logDebugR,
    logInfoR,
    logWarnR,
    logErrorR,

    -- * unwrap
    logUnwrap,
  )
where

import Control.Concurrent.STM
import Control.Exception (Exception, throwIO)
import Control.Monad (unless, when)
import Control.Monad.IO.Class
import Control.Monad.RWS
import Control.Monad.Reader
import Control.Monad.State
import Data.DList qualified as DL
import Data.Time
import System.Directory
import System.FilePath
import System.IO

data LogLevel = L_DEBUG | L_INFO | L_WARN | L_ERROR
  deriving (Eq, Ord, Show, Enum)

newtype LotosApp m a = LotosApp
  { runLotosAppMonad :: StateT LoggerState (ReaderT LogConfig m) a
  }
  deriving
    ( Functor,
      Applicative,
      Monad,
      MonadIO,
      MonadReader LogConfig,
      MonadState LoggerState
    )

type LotosAppMonad = LotosApp IO

data LogConfig = LogConfig
  { confLogLevel :: LogLevel,
    confLogDir :: FilePath,
    confBufferSize :: Int
  }

data LoggerState = LoggerState
  { logEntries :: TVar (DL.DList LogEntry),
    currentDate :: TVar Day,
    logHandle :: TVar Handle
  }

data LogEntry = LogEntry LogLevel ZonedTime String

-- Initialize the logger
initLoggerState :: LogConfig -> IO LoggerState
initLoggerState config = do
  now <- getZonedTime
  let day = localDay (zonedTimeToLocalTime now)
  createDirectoryIfMissing True (confLogDir config)
  handle <- openLogFile config day
  LoggerState
    <$> newTVarIO DL.empty
    <*> newTVarIO day
    <*> newTVarIO handle

openLogFile :: LogConfig -> Day -> IO Handle
openLogFile config day = do
  let fileName = formatTime defaultTimeLocale "%Y-%m-%d.log" day
      path = confLogDir config </> fileName
  openFile path AppendMode

formatEntry :: LogEntry -> String
formatEntry (LogEntry lvl t msg) =
  let timeStr = formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S" t
   in "[" ++ timeStr ++ "] " ++ show lvl ++ ": " ++ msg

flushLogs :: LoggerState -> IO ()
flushLogs st = do
  (entries, handle) <- atomically $ do
    entries <- readTVar (logEntries st)
    handle <- readTVar (logHandle st)
    writeTVar (logEntries st) DL.empty
    return (entries, handle)
  unless (null entries) $ do
    mapM_ (hPutStrLn handle) (map formatEntry (DL.toList entries))
    hFlush handle

rotateIfNeeded :: LogConfig -> LoggerState -> IO ()
rotateIfNeeded config st = do
  now <- getZonedTime
  let today = localDay (zonedTimeToLocalTime now)

  -- Atomically check and update the current date
  shouldRotate <- atomically $ do
    currentDay <- readTVar (currentDate st)
    if currentDay /= today
      then do
        writeTVar (currentDate st) today
        return True
      else return False

  -- If the date has changed, rotate the log file
  when shouldRotate $ do
    -- Flush any remaining logs
    flushLogs st

    -- Close the current log file
    oldHandle <- atomically $ readTVar (logHandle st)
    hClose oldHandle

    -- Open a new log file for the new date
    newHandle <- openLogFile config today
    atomically $ writeTVar (logHandle st) newHandle

logMessage :: LogLevel -> String -> LotosApp IO ()
logMessage level msg = do
  config <- ask
  when (level >= confLogLevel config) $ do
    now <- liftIO getZonedTime
    st <- get
    liftIO $ atomically $ modifyTVar' (logEntries st) (`DL.snoc` LogEntry level now msg)

    entries <- liftIO $ atomically $ readTVar (logEntries st)
    when (length entries >= confBufferSize config) $
      liftIO $
        flushLogs st

    liftIO $ rotateIfNeeded config st

-- Public logging functions
logDebugR, logInfoR, logWarnR, logErrorR :: String -> LotosApp IO ()
logDebugR = logMessage L_DEBUG
logInfoR = logMessage L_INFO
logWarnR = logMessage L_WARN
logErrorR = logMessage L_ERROR

-- Runner function
runLotosApp :: LogConfig -> LotosAppMonad a -> IO (a, LoggerState)
runLotosApp config (LotosApp action) = do
  initialState <- initLoggerState config
  result <- runReaderT (evalStateT action initialState) config
  -- Rotate logs if needed and flush remaining logs
  rotateIfNeeded config initialState
  flushLogs initialState
  return (result, initialState)

runLotosAppWithState :: LogConfig -> LoggerState -> LotosAppMonad a -> IO a
runLotosAppWithState config st (LotosApp action) =
  runReaderT (evalStateT action st) config

-- Error handling helper
logUnwrap ::
  (Exception e, m ~ LotosApp IO) =>
  (String -> m ()) ->
  (e -> String) ->
  IO (Either e a) ->
  m a
logUnwrap logger formatErr action = do
  result <- liftIO action
  case result of
    Left err -> do
      logger (formatErr err)
      liftIO $ throwIO err
    Right x -> return x
