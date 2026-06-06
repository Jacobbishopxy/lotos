module LiveStatus
  ( AliveStatus (..),
    withAliveStatus,
  )
where

import Control.Concurrent (ThreadId, forkIO, killThread, threadDelay)
import Control.Exception (bracket)
import Control.Monad (forever)
import Data.List (intercalate)
import Data.Time (defaultTimeLocale, formatTime, getZonedTime)
import System.IO (Handle, hFlush, hIsTerminalDevice, hPutStr, hPutStrLn, stdout)

-- | Small foreground status printer for long-running demo roles.
--
-- Detailed runtime state is available through the dashboard and log files. The
-- terminal should therefore stay calm: interactive terminals get one rewritten
-- alive line; redirected output gets periodic newline records.
data AliveStatus = AliveStatus
  { aliveRole :: String,
    aliveDetails :: [String],
    aliveIntervalSec :: Int
  }

withAliveStatus :: AliveStatus -> IO a -> IO a
withAliveStatus status action =
  bracket (startAliveStatus status) stopAliveStatus (const action)

data RunningAliveStatus = RunningAliveStatus
  { runningThread :: ThreadId,
    runningHandle :: Handle,
    runningInline :: Bool,
    runningStatus :: AliveStatus
  }

startAliveStatus :: AliveStatus -> IO RunningAliveStatus
startAliveStatus status = do
  inline <- hIsTerminalDevice stdout
  line <- renderStatus status "running; press Ctrl+C to stop"
  hPutStrLn stdout line
  hFlush stdout
  tid <- forkIO $ aliveLoop stdout inline status
  pure $ RunningAliveStatus tid stdout inline status

stopAliveStatus :: RunningAliveStatus -> IO ()
stopAliveStatus running = do
  killThread $ runningThread running
  clearInline (runningHandle running) (runningInline running)
  line <- renderStatus (runningStatus running) "stopped"
  hPutStrLn (runningHandle running) line
  hFlush $ runningHandle running

aliveLoop :: Handle -> Bool -> AliveStatus -> IO ()
aliveLoop handle inline status = forever $ do
  threadDelay $ max 1 (aliveIntervalSec status) * 1_000_000
  line <- renderStatus status "alive"
  if inline
    then hPutStr handle ('\r' : line <> "\ESC[K")
    else hPutStrLn handle line
  hFlush handle

clearInline :: Handle -> Bool -> IO ()
clearInline handle inline =
  if inline
    then hPutStr handle "\r\ESC[K" >> hFlush handle
    else pure ()

renderStatus :: AliveStatus -> String -> IO String
renderStatus status state = do
  now <- getZonedTime
  let timeStr = formatTime defaultTimeLocale "%H:%M:%S" now
      detailText = case aliveDetails status of
        [] -> ""
        xs -> " | " <> intercalate " | " xs
  pure $ "[" <> timeStr <> "] " <> aliveRole status <> " " <> state <> detailText
