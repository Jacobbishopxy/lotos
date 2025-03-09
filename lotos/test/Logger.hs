-- file: Logger.hs
-- author: Jacob Xie
-- date: 2025/03/09 22:39:53 Sunday
-- brief:

module Main where

import Control.Monad.Reader
import Lotos.Logger

app :: LotosAppMonad ()
app = do
  logDebugR "This debug message won't be logged"
  logInfoR "This info message will be logged"
  logWarnR "This warning message will be logged"
  logErrorR "This error message will be logged"

main :: IO ()
main = do
  logger <- createLogger L_INFO
  runReaderT app logger
