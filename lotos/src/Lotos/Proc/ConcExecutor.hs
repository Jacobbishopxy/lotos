-- file: ConcExecutor.hs
-- author: Jacob Xie
-- date: 2025/04/30 09:15:49 Wednesday
-- brief:

module Lotos.Proc.ConcExecutor
  ( CommandRequest (..),
    CommandResult (..),
    simpleCommandRequest,
    executeConcurrently,
  )
where

import Control.Concurrent.Async (async, mapConcurrently, wait)
import Control.Exception.Base (catch, finally, throwIO)
import Data.Time (UTCTime, getCurrentTime)
import Lotos.TSD.RingBuffer
import System.Exit (ExitCode (..))
import System.IO
  ( BufferMode (LineBuffering),
    hClose,
    hGetLine,
    hSetBuffering,
  )
import System.IO.Error (isEOFError)
import System.Process
  ( CreateProcess (std_err, std_out),
    StdStream (CreatePipe),
    createProcess,
    shell,
    waitForProcess,
  )
import System.Timeout (timeout)

-- | Request to execute a shell command with optional timeout and output buffer
data CommandRequest = CommandRequest
  { cmdString :: String, -- Command to be executed
    cmdTimeout :: Int, -- Timeout in seconds: <= 0 means no timeout
    cmdBuffer :: TSRingBuffer String -- Buffer to store command output
  }

-- | Create a simple command request with a default timeout and buffer
simpleCommandRequest :: String -> IO CommandRequest
simpleCommandRequest cmd = do
  buf <- mkTSRingBuffer 16 -- Create a ring buffer with a capacity of 16
  return $ CommandRequest cmd 0 buf -- No timeout specified

-- | Result of a command execution with combined output and timestamp
data CommandResult = CommandResult
  { cmdExitCode :: ExitCode, -- Exit code of the command
    cmdStartTime :: UTCTime, -- Timestamp when command execution started
    cmdEndTime :: UTCTime -- Optional end time of command execution
  }

-- | Execute multiple shell commands concurrently with live output streaming
-- Each command's STDOUT and STDERR are captured and written to the provided buffer
executeConcurrently ::
  -- | List of command requests containing command string, timeout, and output buffer
  [CommandRequest] ->
  IO [CommandResult]
executeConcurrently tasks = mapConcurrently runTask tasks
  where
    -- \| Run a single command task
    runTask CommandRequest {cmdString = cmd, cmdTimeout = to, cmdBuffer = outputBuf} = do
      startT <- getCurrentTime
      (_, Just hout, Just herr, ph) <-
        createProcess (shell cmd) {std_out = CreatePipe, std_err = CreatePipe}

      hSetBuffering hout LineBuffering
      hSetBuffering herr LineBuffering

      exitCode <-
        if to <= 0
          then concurrentlyStream hout herr ph outputBuf `finally` cleanup hout herr
          else do
            let timeoutMicros = to * 1000000 -- Convert seconds to microseconds
            result <- timeout timeoutMicros (concurrentlyStream hout herr ph outputBuf)
            cleanup hout herr
            case result of
              Just ec -> return ec
              Nothing -> do
                writeBuffer outputBuf "SYSTEM: Command timed out"
                return $ ExitFailure 124 -- Standard timeout exit code
      endT <- getCurrentTime
      pure $ CommandResult exitCode startT endT

    -- \| Stream output from both stdout and stderr concurrently
    concurrentlyStream hout herr ph buf = do
      outAsync <- async $ streamOutput hout "STDOUT" buf
      errAsync <- async $ streamOutput herr "STDERR" buf
      ec <- waitForProcess ph -- Wait for the external process to finish
      _ <- wait outAsync -- Ensure stdout thread completes
      _ <- wait errAsync -- Ensure stderr thread completes
      return ec

    -- \| Close both stdout and stderr handles
    cleanup hout herr = hClose hout >> hClose herr

    -- \| Continuously read lines from a handle and write to the ring buffer
    -- Terminates cleanly on EOF
    streamOutput hdl prefix outputBuf =
      let loop = do
            line <- catch (Just <$> hGetLine hdl) handleEOF
            case line of
              Just l -> writeBuffer outputBuf (prefix ++ ": " ++ l) >> loop
              Nothing -> pure () -- EOF reached
              -- Handle EOF by returning Nothing; rethrow unexpected exceptions
          handleEOF e
            | isEOFError e = return Nothing
            | otherwise = throwIO e
       in loop
