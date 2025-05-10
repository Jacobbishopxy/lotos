-- file: Logger.hs
-- author: Jacob Xie
-- date: 2025/03/09 22:39:53 Sunday
-- brief:

module Main where

import Control.Concurrent (forkIO)
import Control.Monad (forM_, void)
import Control.Monad.RWS
import Lotos.Logger

app :: LotosAppMonad ()
app = do
  logDebugR "This debug message won't be logged"
  logInfoR "This info message will be logged"
  logWarnR "This warning message will be logged"
  logErrorR "This error message will be logged"

  liftIO $ putStrLn "Running multi-threaded logging test..."
  threadedApp

-- A test application that logs messages from multiple threads
threadedApp :: LotosAppMonad ()
threadedApp = do
  let threadCount = 5

  -- Get the current configuration and logger state
  config <- ask
  loggerState <- get

  -- Spawn multiple threads
  liftIO $ forM_ [(1 :: Int) .. threadCount] $ \threadId -> do
    forkIO $
      runLotosAppWithState config loggerState $ do
        logInfoR $ "Thread " ++ show threadId ++ " logging info"
        logWarnR $ "Thread " ++ show threadId ++ " logging warning"
        logErrorR $ "Thread " ++ show threadId ++ " logging error"

main :: IO ()
main = do
  let config =
        LogConfig
          { confLogLevel = L_INFO,
            confLogDir = "./logs",
            confBufferSize = 10
          }
  putStrLn "Running logging tests..."
  void $ runLotosApp config app
