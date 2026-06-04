{-# LANGUAGE RecordWildCards #-}

module Lotos.Zmq.Internal.HandoffQueueStats
  ( HandoffQueueStats (..),
    HandoffQueueStatsVar,
    HandoffQueueRegistry,
    newHandoffQueueStats,
    readHandoffQueueStats,
    recordHandoffEnqueue,
    recordHandoffEnqueueN,
    recordHandoffDrain,
    recordHandoffEnqueueSTM,
    recordHandoffEnqueueNSTM,
    recordHandoffDrainSTM,
    takeHandoffQueueWarning,
    newHandoffQueueRegistry,
    registerHandoffQueueStats,
    readHandoffQueueRegistry,
  )
where

import Control.Concurrent.STM
import Data.Aeson ((.=))
import Data.Aeson qualified as Aeson
import Data.Text (Text)

-- | Lightweight public snapshot for no-drop EventLoop handoff queues.
data HandoffQueueStats = HandoffQueueStats
  { hqsName :: Text,
    hqsCurrentDepth :: Int,
    hqsHighWaterDepth :: Int,
    hqsTotalEnqueued :: Int,
    hqsTotalDrained :: Int,
    hqsWarningThreshold :: Int
  }
  deriving (Show, Eq)

instance Aeson.ToJSON HandoffQueueStats where
  toJSON HandoffQueueStats {..} =
    Aeson.object
      [ "name" .= hqsName,
        "currentDepth" .= hqsCurrentDepth,
        "highWaterDepth" .= hqsHighWaterDepth,
        "totalEnqueued" .= hqsTotalEnqueued,
        "totalDrained" .= hqsTotalDrained,
        "warningThreshold" .= hqsWarningThreshold
      ]

data HandoffQueueState = HandoffQueueState
  { hqsSnapshot :: HandoffQueueStats,
    hqsLastWarningDepth :: Int,
    hqsPendingWarning :: Maybe HandoffQueueStats
  }

newtype HandoffQueueStatsVar = HandoffQueueStatsVar (TVar HandoffQueueState)

newtype HandoffQueueRegistry = HandoffQueueRegistry (TVar [HandoffQueueStatsVar])

newHandoffQueueStats :: Text -> Int -> IO HandoffQueueStatsVar
newHandoffQueueStats hqsName warningThreshold =
  HandoffQueueStatsVar
    <$> newTVarIO
      HandoffQueueState
        { hqsSnapshot =
            HandoffQueueStats
              { hqsName = hqsName,
                hqsCurrentDepth = 0,
                hqsHighWaterDepth = 0,
                hqsTotalEnqueued = 0,
                hqsTotalDrained = 0,
                hqsWarningThreshold = max 0 warningThreshold
              },
          hqsLastWarningDepth = 0,
          hqsPendingWarning = Nothing
        }

readHandoffQueueStats :: HandoffQueueStatsVar -> IO HandoffQueueStats
readHandoffQueueStats (HandoffQueueStatsVar stateVar) =
  hqsSnapshot <$> readTVarIO stateVar

recordHandoffEnqueue :: HandoffQueueStatsVar -> IO ()
recordHandoffEnqueue statsVar = atomically $ recordHandoffEnqueueSTM statsVar

recordHandoffEnqueueN :: Int -> HandoffQueueStatsVar -> IO ()
recordHandoffEnqueueN count statsVar = atomically $ recordHandoffEnqueueNSTM count statsVar

recordHandoffDrain :: Int -> HandoffQueueStatsVar -> IO ()
recordHandoffDrain count statsVar = atomically $ recordHandoffDrainSTM count statsVar

recordHandoffEnqueueSTM :: HandoffQueueStatsVar -> STM ()
recordHandoffEnqueueSTM statsVar = recordHandoffEnqueueNSTM 1 statsVar

recordHandoffEnqueueNSTM :: Int -> HandoffQueueStatsVar -> STM ()
recordHandoffEnqueueNSTM count (HandoffQueueStatsVar stateVar) =
  modifyTVar' stateVar $ applyEnqueue (max 0 count)

recordHandoffDrainSTM :: Int -> HandoffQueueStatsVar -> STM ()
recordHandoffDrainSTM count (HandoffQueueStatsVar stateVar) =
  modifyTVar' stateVar $ applyDrain (max 0 count)

takeHandoffQueueWarning :: HandoffQueueStatsVar -> IO (Maybe HandoffQueueStats)
takeHandoffQueueWarning (HandoffQueueStatsVar stateVar) =
  atomically $ do
    state@HandoffQueueState {..} <- readTVar stateVar
    writeTVar stateVar state {hqsPendingWarning = Nothing}
    pure hqsPendingWarning

newHandoffQueueRegistry :: IO HandoffQueueRegistry
newHandoffQueueRegistry = HandoffQueueRegistry <$> newTVarIO []

registerHandoffQueueStats :: HandoffQueueRegistry -> HandoffQueueStatsVar -> IO ()
registerHandoffQueueStats (HandoffQueueRegistry registryVar) statsVar =
  atomically $ modifyTVar' registryVar (statsVar :)

readHandoffQueueRegistry :: HandoffQueueRegistry -> IO [HandoffQueueStats]
readHandoffQueueRegistry (HandoffQueueRegistry registryVar) = do
  statsVars <- reverse <$> readTVarIO registryVar
  traverse readHandoffQueueStats statsVars

applyEnqueue :: Int -> HandoffQueueState -> HandoffQueueState
applyEnqueue 0 state = state
applyEnqueue count state@HandoffQueueState {hqsSnapshot = snapshot@HandoffQueueStats {..}, ..} =
  let newDepth = hqsCurrentDepth + count
      newHighWater = max hqsHighWaterDepth newDepth
      newSnapshot =
        snapshot
          { hqsCurrentDepth = newDepth,
            hqsHighWaterDepth = newHighWater,
            hqsTotalEnqueued = hqsTotalEnqueued + count
          }
      crossedNewHighWater = newHighWater > hqsHighWaterDepth
      warningDue =
        crossedNewHighWater
          && hqsWarningThreshold > 0
          && newHighWater >= hqsWarningThreshold
          && (hqsLastWarningDepth == 0 || newHighWater >= hqsLastWarningDepth * 2)
   in state
        { hqsSnapshot = newSnapshot,
          hqsLastWarningDepth = if warningDue then newHighWater else hqsLastWarningDepth,
          hqsPendingWarning = if warningDue then Just newSnapshot else hqsPendingWarning
        }

applyDrain :: Int -> HandoffQueueState -> HandoffQueueState
applyDrain 0 state = state
applyDrain count state@HandoffQueueState {hqsSnapshot = snapshot@HandoffQueueStats {..}} =
  state
    { hqsSnapshot =
        snapshot
          { hqsCurrentDepth = max 0 (hqsCurrentDepth - count),
            hqsTotalDrained = hqsTotalDrained + count
          }
    }
