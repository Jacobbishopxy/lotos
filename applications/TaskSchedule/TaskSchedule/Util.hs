{-# LANGUAGE RecordWildCards #-}

-- file: Util.hs
-- author: Jacob Xie
-- date: 2025/04/16 14:04:56 Wednesday
-- brief:

module TaskSchedule.Util
  ( cvtCommandResult2TaskStatus,
  )
where

import Lotos.Proc
import Lotos.Zmq
import System.Exit

cvtCommandResult2TaskStatus :: CommandResult -> TaskStatus
cvtCommandResult2TaskStatus CommandResult {..} =
  if cmdExitCode == ExitSuccess then TaskSucceed else TaskFailed
