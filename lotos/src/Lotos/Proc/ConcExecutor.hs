-- file: ConcExecutor.hs
-- author: Jacob Xie
-- date: 2025/04/30 09:15:49 Wednesday
-- brief:

module Lotos.Proc.ConcExecutor
  ( CommandRequest (..),
    CommandResult (..),
    simpleCommandRequest,
    simpleCommandRequestWithBuffer,
    executeConcurrently,
  )
where

import Control.Concurrent.Async (async, mapConcurrently, wait)
import Control.Exception
  ( IOException,
    catch,
    handle,
    throwIO,
  )
import Data.List (partition)
import Data.Maybe (isJust)
import Data.Time (UTCTime, getCurrentTime)
import Lotos.TSD.RingBuffer
  ( TSRingBuffer,
    writeBuffer,
  )
import System.Exit (ExitCode (..))
import System.IO
  ( BufferMode (LineBuffering),
    Handle,
    hClose,
    hGetLine,
    hSetBuffering,
  )
import System.IO.Error (isEOFError)
import System.Process
  ( CreateProcess (std_err, std_out),
    ProcessHandle,
    StdStream (CreatePipe),
    createProcess,
    shell,
    terminateProcess,
    waitForProcess,
  )
import System.Timeout (timeout)

-- | Request to execute a shell command with optional timeout and output buffer
data CommandRequest
  = CommandRequest
  { cmdString :: String,
    cmdTimeout :: Int,
    loggingIO :: String -> IO (),
    startIO :: IO (),
    finishIO :: CommandResult -> IO ()
  }

-- | Create a simple command request with a default timeout and buffer
simpleCommandRequest :: String -> CommandRequest
simpleCommandRequest cmd =
  CommandRequest cmd 0 (\_ -> return ()) (return ()) (\_ -> return ())

-- | Create a simple command request with a buffer for output logging
simpleCommandRequestWithBuffer :: String -> Int -> TSRingBuffer String -> CommandRequest
simpleCommandRequestWithBuffer cmd to buf =
  CommandRequest cmd to (writeBuffer buf) (return ()) (\_ -> return ())

-- | Result of a command execution with combined output and timestamp
data CommandResult = CommandResult
  { cmdExitCode :: ExitCode, -- Exit code of the command
    cmdStartTime :: UTCTime, -- Timestamp when command execution started
    cmdEndTime :: UTCTime -- Optional end time of command execution
  }
  deriving (Show)

-- | Execute multiple shell commands concurrently with live output streaming
-- Each command's STDOUT and STDERR are captured and processed according to the request type
executeConcurrently :: [CommandRequest] -> IO [CommandResult]
executeConcurrently cmds = mapConcurrently runTask cmds
  where
    -- Process a single command request
    runTask (CommandRequest cmd to handler start finish) = do
      start
      result <- runCommand cmd to handler
      finish result
      return result

----------------------------------------------------------------------------------------------------
-- helpers

-- | Core command execution logic shared by both request variants
-- @param cmd The shell command to execute
-- @param to Timeout in seconds (<= 0 means no timeout)
-- @param handler Function to process command output (either buffer write or custom IO)
runCommand :: String -> Int -> (String -> IO ()) -> IO CommandResult
runCommand cmd to handler = do
  startT <- getCurrentTime -- Record start time for CommandResult
  -- Create process with pipes for stdout/stderr
  (_, Just hout, Just herr, ph) <-
    createProcess (shell cmd) {std_out = CreatePipe, std_err = CreatePipe}

  -- Set line buffering for real-time output processing
  hSetBuffering hout LineBuffering
  hSetBuffering herr LineBuffering

  -- Start streaming output immediately
  outputAsync <- async $ streamOutputs [(hout, "STDOUT"), (herr, "STDERR")] handler

  -- Handle timeout on waiting for the process
  exitCode <- handleTimeout to (waitForProcess ph) ph

  -- Wait for output streaming to finish processing all remaining data
  wait outputAsync

  -- Cleanup handles after streaming is done
  cleanup hout herr

  endT <- getCurrentTime -- Record end time for CommandResult
  pure $ CommandResult exitCode startT endT

-- | Continuously read lines from multiple handles and apply the handler
-- Handles EOF and IO exceptions properly
-- @param handles List of (Handle, prefix) pairs to read from
-- @param handler Function to process each output line
streamOutputs :: [(Handle, String)] -> (String -> IO ()) -> IO ()
streamOutputs handles handler = do
  let readHandle (hdl, prefix) = catch (Just . (prefix,) <$> hGetLine hdl) $ \e ->
        if isEOFError e then return Nothing else throwIO e
  let loop remaining
        | null remaining = pure ()
        | otherwise = do
            -- Read from all active handles
            results <- mapM readHandle remaining
            -- Partition active/inactive handles
            let (active, _) = partition (isJust . snd) $ zip remaining results
            -- Process output from active handles
            mapM_
              ( \case
                  (_, Just (prefix, line)) -> handler $ prefix ++ ": " ++ line
                  (_, Nothing) -> return ()
              )
              active
            -- Continue with remaining active handles
            loop (map fst active)
  loop handles

-- | Handle command execution with optional timeout
-- @param to Timeout in seconds (<= 0 means no timeout)
-- @param action The IO action to execute (waiting for the process)
-- @param ph ProcessHandle for timeout termination
handleTimeout :: Int -> IO ExitCode -> ProcessHandle -> IO ExitCode
handleTimeout to action ph
  | to <= 0 = action -- No timeout case
  | otherwise =
      -- Convert to microseconds
      timeout (to * 1000000) action >>= \case
        -- Action completed before timeout
        Just x -> return x
        -- Timeout occurred: terminate the process and wait for it
        Nothing -> terminateProcess ph >> waitForProcess ph >> return (ExitFailure 124)

-- | Safely close both stdout and stderr handles
-- Silently handles any IO exceptions during close
cleanup :: Handle -> Handle -> IO ()
cleanup hout herr = do
  handle (\(_ :: IOException) -> return ()) $ hClose hout
  handle (\(_ :: IOException) -> return ()) $ hClose herr
