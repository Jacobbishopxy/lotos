-- file: Logger.hs
-- author: Jacob Xie
-- date: 2024/09/18 09:39:27 Wednesday
-- brief:

module Lotos.Logger
  ( LogLevel (..),
    LoggerEnv,
    LotosApp,
    runApp,
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

import Control.Concurrent (ThreadId, forkIO, myThreadId, threadDelay)
import Control.Concurrent.Async (Async, async, cancel)
import Control.Exception (SomeException, bracket, handle)
import Control.Monad (forever, when)
import Control.Monad.Reader
import Data.Time
import System.Directory (createDirectoryIfMissing, doesFileExist, getModificationTime, renameFile)
import System.FilePath (takeDirectory)
import System.Log.FastLogger

-- Log level definitions
data LogLevel = DEBUG | INFO | WARN | ERROR deriving (Show, Eq, Ord)

-- Logger environment
data LoggerEnv = LoggerEnv
  { loggerSet :: LoggerSet,
    consoleLogger :: Maybe LoggerSet,
    minLogLevel :: LogLevel,
    currentLogPath :: FilePath,
    rotationThread :: Maybe (Async ())
  }

newtype LotosApp a = LotosApp
  { unApp :: ReaderT LoggerEnv IO a
  }
  deriving (Functor, Applicative, Monad, MonadIO, MonadReader LoggerEnv)

runApp :: LoggerEnv -> LotosApp a -> IO a
runApp env app = runReaderT (unApp app) env

-- Fork an App action as a new thread
forkApp :: LotosApp () -> LotosApp ThreadId
forkApp action = do
  env <- ask -- Capture the current environment
  liftIO $ forkIO (runApp env action) -- Run the action in the new thread

-- Helper function for logging
logApp :: LogLevel -> String -> LotosApp ()
logApp level msg = do
  logger <- ask
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

  return $ LoggerEnv set console minLevel logPath (Just rotationThread)

-- Initialize logger with console output only
initConsoleLogger :: LogLevel -> IO LoggerEnv
initConsoleLogger minLevel = do
  set <- newStdoutLoggerSet defaultBufSize
  return $ LoggerEnv set Nothing minLevel "" Nothing

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
