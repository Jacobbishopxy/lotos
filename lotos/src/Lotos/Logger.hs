-- file: Logger.hs
-- author: Jacob Xie
-- date: 2024/09/18 09:39:27 Wednesday
-- brief:

module Lotos.Logger
  ( LogLevel (..),
    LoggerEnv,
    LotosEnv (..),
    LotosApp,
    askLoggerEnv,
    askZmqContext,
    runApp,
    runZmqApp,
    runZmqAppWithThread,
    runAppWithContext,
    runAppWithEnv,
    forkApp,
    logApp,
    initLocalTimeLogger,
    withLocalTimeLogger,
    initConsoleLogger,
    withConsoleLogger,
    logMessage,
    closeLogger,
    getCurrentLogPath,
  )
where

import Control.Concurrent (ThreadId, forkIO, killThread, myThreadId, threadDelay)
import Control.Concurrent.Async (Async, async, cancel)
import Control.Concurrent.MVar (MVar, modifyMVar, modifyMVar_, newEmptyMVar, newMVar, putMVar, readMVar)
import Control.Exception (SomeException, bracket, finally, handle)
import Control.Monad (forever, when)
import Control.Monad.Reader
import Data.Time
import GHC.Natural (Natural)
import System.Directory (createDirectoryIfMissing, doesFileExist, getModificationTime, renameFile)
import System.FilePath (takeDirectory)
import System.Log.FastLogger
import Zmqx qualified
import Zmqx.Monad qualified as ZmqxM

-- Log level definitions
data LogLevel = DEBUG | INFO | WARN | ERROR deriving (Show, Eq, Ord)

-- Logger environment
data LoggerEnv = LoggerEnv
  { loggerSet :: LoggerSet,
    consoleLogger :: Maybe LoggerSet,
    minLogLevel :: LogLevel,
    currentLogPath :: FilePath,
    rotationThread :: Maybe (Async ()),
    childThreads :: MVar [(ThreadId, MVar ())]
  }

data LotosEnv = LotosEnv
  { lotosLoggerEnv :: LoggerEnv,
    lotosZmqContext :: Zmqx.Context
  }

newtype LotosApp a = LotosApp
  { unApp :: ReaderT LotosEnv IO a
  }
  deriving (Functor, Applicative, Monad, MonadIO, MonadReader LotosEnv)

instance ZmqxM.MonadZmqx LotosApp where
  askContext = asks lotosZmqContext

askLoggerEnv :: LotosApp LoggerEnv
askLoggerEnv = asks lotosLoggerEnv

askZmqContext :: LotosApp Zmqx.Context
askZmqContext = asks lotosZmqContext

runAppWithEnv :: LotosEnv -> LotosApp a -> IO a
runAppWithEnv env app = runReaderT (unApp app) env

runAppWithContext :: Zmqx.Context -> LoggerEnv -> LotosApp a -> IO a
runAppWithContext context loggerEnv action =
  runAppWithEnv (LotosEnv loggerEnv context) action
    `finally` cancelForkedAppThreads (childThreads loggerEnv)

cancelForkedAppThreads :: MVar [(ThreadId, MVar ())] -> IO ()
cancelForkedAppThreads childRegistry = do
  children <- modifyMVar childRegistry $ \children -> pure ([], children)
  mapM_ (killThread . fst) children
  mapM_ (readMVar . snd) children

runZmqApp :: LoggerEnv -> LotosApp a -> IO a
runZmqApp loggerEnv action =
  Zmqx.withContext Zmqx.defaultOptions $ \context ->
    runAppWithContext context loggerEnv action

runZmqAppWithThread :: Natural -> LoggerEnv -> LotosApp a -> IO a
runZmqAppWithThread threadNum loggerEnv action =
  Zmqx.withContext (Zmqx.ioThreads threadNum) $ \context ->
    runAppWithContext context loggerEnv action

-- | Compatibility runner for existing logger-only call sites.
--
-- Prefer 'runZmqApp' at ZMQ application entry points so the context lifetime is
-- explicit at the call site.
runApp :: LoggerEnv -> LotosApp a -> IO a
runApp = runZmqApp

-- Fork an App action as a new thread
forkApp :: LotosApp () -> LotosApp ThreadId
forkApp action = do
  env <- ask -- Capture the current logger and ZMQ context
  done <- liftIO newEmptyMVar
  tid <- liftIO $ forkIO (runAppWithEnv env action `finally` putMVar done ()) -- Run the action in the new thread
  liftIO $ modifyMVar_ (childThreads $ lotosLoggerEnv env) $ \children -> pure ((tid, done) : children)
  pure tid

-- Helper function for logging
logApp :: LogLevel -> String -> LotosApp ()
logApp level msg = do
  logger <- askLoggerEnv
  liftIO $ logMessage logger level msg

----------------------------------------------------------------------------------------------------

-- Initialize logger with local time daily rotation
initLocalTimeLogger :: FilePath -> LogLevel -> Bool -> IO LoggerEnv
initLocalTimeLogger logPath minLevel withConsole = do
  -- Ensure directory exists
  createDirectoryIfMissing True (takeDirectory logPath)

  -- Rotate if needed based on local time
  rotateIfNeededLocal logPath

  -- Create logger set
  set <- newFileLoggerSet defaultBufSize logPath

  -- Create console logger if requested
  console <- if withConsole then Just <$> newStdoutLoggerSet defaultBufSize else return Nothing

  -- Start rotation monitor thread using local time
  rotationThread <- async (localTimeRotationMonitor logPath set)
  childRegistry <- newMVar []

  return $ LoggerEnv set console minLevel logPath (Just rotationThread) childRegistry

-- Initialize logger with console output only
initConsoleLogger :: LogLevel -> IO LoggerEnv
initConsoleLogger minLevel = do
  set <- newStdoutLoggerSet defaultBufSize
  childRegistry <- newMVar []
  return $ LoggerEnv set Nothing minLevel "" Nothing childRegistry

-- Resource-safe logger usage
withLocalTimeLogger :: FilePath -> LogLevel -> Bool -> (LoggerEnv -> IO a) -> IO a
withLocalTimeLogger path level withConsole =
  bracket (initLocalTimeLogger path level withConsole) closeLogger

-- Resource-safe console logger usage
withConsoleLogger :: LogLevel -> (LoggerEnv -> IO a) -> IO a
withConsoleLogger level =
  bracket (initConsoleLogger level) closeLogger

-- Close logger and cleanup
closeLogger :: LoggerEnv -> IO ()
closeLogger env = do
  case rotationThread env of
    Just t -> cancel t
    Nothing -> return ()
  rmLoggerSet (loggerSet env)

-- Core logging function with local timestamps
logMessage :: (MonadIO m) => LoggerEnv -> LogLevel -> String -> m ()
logMessage env level msg
  | level < minLogLevel env = return ()
  | otherwise = liftIO $ do
      now <- getZonedTime
      tid <- myThreadId
      let timeStr = formatTime defaultTimeLocale "%F %T.%q" now
          levelStr = padRight 5 ' ' (show level)
          tidStr = drop 9 (show tid)
          logEntry = "[" ++ timeStr ++ "][" ++ tidStr ++ "][" ++ levelStr ++ "] " ++ msg ++ "\n"
      -- Log to file
      pushLogStr (loggerSet env) $ toLogStr logEntry
      -- Log to console if configured
      case consoleLogger env of
        Just console -> pushLogStr console $ toLogStr logEntry
        Nothing -> return ()
  where
    padRight n c s = s ++ replicate (n - length s) c

-- Get the current log path
getCurrentLogPath :: LoggerEnv -> FilePath
getCurrentLogPath = currentLogPath

-- Local time rotation monitor thread
localTimeRotationMonitor :: FilePath -> LoggerSet -> IO ()
localTimeRotationMonitor logPath set =
  handle (\(_ :: SomeException) -> return ()) $ -- Prevent thread death
    forever $ do
      now <- getZonedTime
      let localTime = zonedTimeToLocalTime now
          today = localDay localTime
          tomorrow = addDays 1 today
          midnightTonight = LocalTime tomorrow midnight
          nextRotation = localTimeToUTC (zonedTimeZone now) midnightTonight

      -- Wait until local midnight
      nowUTC <- getCurrentTime
      let diff = diffUTCTime nextRotation nowUTC
      threadDelay (floor (diff * 1000000)) -- Convert to microseconds

      -- Rotate logs
      rotateLogLocalTime logPath set

      -- Recreate logger set for new day
      rmLoggerSet set
      newFileLoggerSet defaultBufSize logPath

-- Rotate logs if needed based on local time
rotateIfNeededLocal :: FilePath -> IO ()
rotateIfNeededLocal logPath = do
  exists <- doesFileExist logPath
  when exists $ do
    modTimeUTC <- getModificationTime logPath
    timeZone <- getCurrentTimeZone
    let modTimeLocal = utcToLocalTime timeZone modTimeUTC
        modDay = localDay modTimeLocal

    currentLocalTime <- getZonedTime
    let currentDay = localDay (zonedTimeToLocalTime currentLocalTime)

    when (modDay < currentDay) $ do
      let suffix = formatTime defaultTimeLocale "%Y-%m-%d" modTimeLocal
          newName = logPath ++ "." ++ suffix
      renameFile logPath newName

-- Perform log rotation using local time
rotateLogLocalTime :: FilePath -> LoggerSet -> IO ()
rotateLogLocalTime logPath set = do
  -- Flush current logs
  flushLogStr set

  -- Close current file
  rmLoggerSet set

  -- Rotate if file exists
  exists <- doesFileExist logPath
  when exists $ do
    modTimeUTC <- getModificationTime logPath
    timeZone <- getCurrentTimeZone
    let modTimeLocal = utcToLocalTime timeZone modTimeUTC
        suffix = formatTime defaultTimeLocale "%Y-%m-%d" modTimeLocal
        newName = logPath ++ "." ++ suffix
    renameFile logPath newName
