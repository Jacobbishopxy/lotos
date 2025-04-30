-- file: Proc.hs
-- author: Jacob Xie
-- date: 2025/04/30 09:15:56 Wednesday
-- brief:

module Lotos.Proc
  ( -- * ConcExecutor
    executeConcurrently,
    CommandResult (..),
  )
where

import Lotos.Proc.ConcExecutor
