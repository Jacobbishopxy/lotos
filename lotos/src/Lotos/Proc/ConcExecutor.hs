-- file: ConcExecutor.hs
-- author: Jacob Xie
-- date: 2025/04/30 09:15:49 Wednesday
-- brief:

module Lotos.Proc.ConcExecutor
  ( executeConcurrently,
    CommandResult (..),
  )
where

import Control.Concurrent.Async (async, mapConcurrently, wait)
import Control.Exception.Base (catch, finally, throwIO)
import Data.Time (UTCTime, getCurrentTime)
import Lotos.TSD.RingBuffer (TSRingBuffer, writeBuffer)
import System.Exit (ExitCode)
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

-- | Result of a command execution with combined output and timestamp
data CommandResult = CommandResult
  { cmdExitCode :: ExitCode, -- Exit code of the command
    cmdStartTime :: UTCTime, -- Timestamp when command execution started
    cmdEndTime :: UTCTime -- Optional end time of command execution
  }

-- | Execute multiple shell commands concurrently with live output streaming
-- Each command's STDOUT and STDERR are captured and written to the provided buffer
executeConcurrently ::
  -- | List of (command string, output ring buffer)
  [(String, TSRingBuffer String)] ->
  IO [CommandResult]
executeConcurrently tasks = mapConcurrently runTask tasks
  where
    -- \| Run a single command task
    runTask (cmd, outputBuf) = do
      startT <- getCurrentTime -- Capture start time
      -- Launch the process with separate pipes for stdout and stderr
      (_, Just hout, Just herr, ph) <-
        createProcess (shell cmd) {std_out = CreatePipe, std_err = CreatePipe}

      -- Optional: ensure line buffering to avoid blocking on partial lines
      hSetBuffering hout LineBuffering
      hSetBuffering herr LineBuffering

      -- Stream output concurrently from both stdout and stderr, wait for process
      exitCode <-
        (concurrentlyStream hout herr ph outputBuf)
          `finally` (cleanup hout herr) -- Ensure handles are closed
      endT <- getCurrentTime
      -- Return command result
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
