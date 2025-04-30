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
import Control.Exception
  ( IOException,
    catch,
    finally,
    handle,
    throwIO,
  )
import Data.List (partition)
import Data.Maybe (isJust)
import Data.Time (UTCTime, getCurrentTime)
import Lotos.TSD.RingBuffer
  ( TSRingBuffer,
    mkTSRingBuffer,
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
executeConcurrently :: [CommandRequest] -> IO [CommandResult]
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
                terminateProcess ph -- Terminate the process
                _ <- waitForProcess ph -- Clean up process
                return $ ExitFailure 124
      endT <- getCurrentTime
      pure $ CommandResult exitCode startT endT

----------------------------------------------------------------------------------------------------
-- helpers

-- \| Stream output from both stdout and stderr concurrently
concurrentlyStream :: Handle -> Handle -> ProcessHandle -> TSRingBuffer String -> IO ExitCode
concurrentlyStream hout herr ph buf = do
  outputAsync <- async $ streamOutputs [(hout, "STDOUT"), (herr, "STDERR")] buf
  ec <- waitForProcess ph
  _ <- wait outputAsync
  return ec

-- \| Close both stdout and stderr handles
cleanup :: Handle -> Handle -> IO ()
cleanup hout herr = do
  -- Handle exceptions during cleanup
  handle (\(_ :: IOException) -> return ()) $ hClose hout
  handle (\(_ :: IOException) -> return ()) $ hClose herr

-- \| Stream output from handles to the buffer (multi threads
-- streamOutputs' :: [(Handle, String)] -> TSRingBuffer String -> IO ()
-- streamOutputs' handles outputBuf = do
--   let processHandle (hdl, prefix) =
--         catch
--           ( forever $ do
--               line <- hGetLine hdl
--               writeBuffer outputBuf (prefix ++ ": " ++ line)
--           )
--           (\e -> if isEOFError e then return () else throwIO e)
--   asyncs <- mapM (async . processHandle) handles
--   mapM_ wait asyncs

-- \| Continuously read lines from multiple handles and write to the ring buffer (single thread
streamOutputs :: [(Handle, String)] -> TSRingBuffer String -> IO ()
streamOutputs handles outputBuf = do
  let readHandle (hdl, prefix) = catch (Just . (prefix,) <$> hGetLine hdl) $ \e ->
        if isEOFError e then return Nothing else throwIO e
  let loop remaining
        | null remaining = pure ()
        | otherwise = do
            results <- mapM readHandle remaining
            let (active, _) = partition (isJust . snd) $ zip remaining results
            mapM_
              ( \case
                  (_, Just (prefix, line)) -> writeBuffer outputBuf (prefix ++ ": " ++ line)
                  (_, Nothing) -> return ()
              )
              active
            loop (map fst active)
  loop handles