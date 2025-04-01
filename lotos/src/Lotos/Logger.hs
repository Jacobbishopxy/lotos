-- file: Logger.hs
-- author: Jacob Xie
-- date: 2024/09/18 09:39:27 Wednesday
-- brief:

module Lotos.Logger
  ( LogLevel (..),
    LogConfig (..),
    LotosAppMonad,
    runLotosApp,
    logDebugR,
    logInfoR,
    logWarnR,
    logErrorR,

    -- * unwrap
    logUnwrap,
  )
where

import Control.Exception (Exception, throwIO)
import Control.Monad (unless, when)
import Control.Monad.IO.Class
import Control.Monad.RWS
import Data.DList qualified as DL
import Data.Time
import System.Directory
import System.FilePath
import System.IO

data LogLevel = L_DEBUG | L_INFO | L_WARN | L_ERROR
  deriving (Eq, Ord, Show, Enum)

newtype LotosAppMonad a = LotosAppMonad
  { unLotosApp :: RWST LogConfig () LoggerState IO a
  }
  deriving
    ( Functor,
      Applicative,
      Monad,
      MonadIO,
      MonadReader LogConfig,
      MonadState LoggerState
    )

data LogConfig = LogConfig
  { confLogLevel :: LogLevel,
    confLogDir :: FilePath,
    confBufferSize :: Int
  }

data LoggerState = LoggerState
  { logEntries :: DL.DList LogEntry,
    currentDate :: Day,
    logHandle :: Handle
  }

data LogEntry = LogEntry LogLevel ZonedTime String

-- Initialize the logger
initLoggerState :: LogConfig -> IO LoggerState
initLoggerState config = do
  now <- getZonedTime
  let day = localDay (zonedTimeToLocalTime now)
  createDirectoryIfMissing True (confLogDir config)
  handle <- openLogFile config day
  return
    LoggerState
      { logEntries = DL.empty,
        currentDate = day,
        logHandle = handle
      }

openLogFile :: LogConfig -> Day -> IO Handle
openLogFile config day = do
  let fileName = formatTime defaultTimeLocale "%Y-%m-%d.log" day
      path = confLogDir config </> fileName
  openFile path AppendMode

formatEntry :: LogEntry -> String
formatEntry (LogEntry lvl t msg) =
  let timeStr = formatTime defaultTimeLocale "%Y-%m-%d %H:%M:%S" t
   in "[" ++ timeStr ++ "] " ++ show lvl ++ ": " ++ msg

flushLogs :: LoggerState -> IO LoggerState
flushLogs st = do
  let entries = DL.toList (logEntries st)
  unless (null entries) $ do
    mapM_ (hPutStrLn (logHandle st)) (map formatEntry entries)
    hFlush (logHandle st)
  return st {logEntries = DL.empty}

rotateIfNeeded :: LoggerState -> IO LoggerState
rotateIfNeeded st = do
  now <- getZonedTime
  let newDay = localDay (zonedTimeToLocalTime now)
  if newDay /= currentDate st
    then do
      hClose (logHandle st)
      newHandle <- openLogFile (LogConfig undefined undefined undefined) newDay
      return
        st
          { currentDate = newDay,
            logHandle = newHandle
          }
    else return st

logMessage :: LogLevel -> String -> LotosAppMonad ()
logMessage level msg = do
  config <- ask
  when (level >= confLogLevel config) $ do
    now <- liftIO getZonedTime
    modify $ \s ->
      s {logEntries = logEntries s `DL.snoc` LogEntry level now msg}

    st <- get
    when (length (logEntries st) >= confBufferSize config) $ do
      newState <- liftIO (flushLogs st)
      put newState

    -- Check date rotation
    rotatedState <- liftIO (rotateIfNeeded st)
    put rotatedState

-- Public logging functions
logDebugR, logInfoR, logWarnR, logErrorR :: String -> LotosAppMonad ()
logDebugR = logMessage L_DEBUG
logInfoR = logMessage L_INFO
logWarnR = logMessage L_WARN
logErrorR = logMessage L_ERROR

-- Runner function
runLotosApp :: LogConfig -> LotosAppMonad a -> IO a
runLotosApp config action = do
  initialState <- initLoggerState config
  (result, finalState, _) <- runRWST (unLotosApp action) config initialState
  _ <- flushLogs finalState
  hClose (logHandle finalState)
  return result

-- Error handling helper
logUnwrap ::
  (Exception e, MonadIO m) =>
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
