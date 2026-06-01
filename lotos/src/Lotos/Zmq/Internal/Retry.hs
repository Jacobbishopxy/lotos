-- file: Internal/Retry.hs
-- brief: Internal retry-disposition helpers for broker tests and implementation.

-- | Internal retry-disposition helpers.
--
-- These names are intentionally kept out of the public 'Lotos.Zmq' facade.
-- They remain importable from this narrower module for bounded regression tests
-- and broker implementation code that needs to inspect retry readiness directly.
module Lotos.Zmq.Internal.Retry
  ( FailedTaskDisposition (..),
    RetryTask (..),
    failedTaskDisposition,
    mkRetryTask,
    retryTaskEligible,
    partitionRetryTasks,
  )
where

import Lotos.Zmq.Adt
  ( FailedTaskDisposition (..),
    RetryTask (..),
    failedTaskDisposition,
    mkRetryTask,
    partitionRetryTasks,
    retryTaskEligible,
  )
