-- file: Map.hs
-- author: Jacob Xie
-- date: 2025/03/25 10:55:16 Tuesday
-- brief:

module Lotos.TSD.Map
  ( -- * TSMap
    TSMap,
    mkTSMap,
    insertMap,
    lookupMap,
    deleteMap,
    updateMap,
    modifyMap,
    toListMap,
    isEmptyMap,
    getTSMapTVar,
  )
where

import Control.Concurrent.STM
import Data.Map qualified as Map

----------------------------------------------------------------------------------------------------
-- Thread-Safe Worker Status Map (STM-based)
----------------------------------------------------------------------------------------------------

-- A thread-safe map that associates RoutingIDs with worker statuses.
newtype TSMap k v = TSMap (TVar (Map.Map k v))

-- Creates a new empty thread-safe map.
mkTSMap :: IO (TSMap k v)
mkTSMap = TSMap <$> newTVarIO Map.empty

-- Inserts a key-value pair into the map.
insertMap :: (Ord k) => k -> v -> TSMap k v -> IO ()
insertMap k v (TSMap t) = atomically $ modifyTVar' t (Map.insert k v)

-- Looks up a value associated with a given key in the map.
lookupMap :: (Ord k) => k -> TSMap k v -> IO (Maybe v)
lookupMap k (TSMap t) = atomically $ Map.lookup k <$> readTVar t

-- Deletes the entry associated with a key from the map.
deleteMap :: (Ord k) => k -> TSMap k v -> IO ()
deleteMap k (TSMap t) = atomically $ modifyTVar' t (Map.delete k)

-- Updates the value associated with a key using the provided function.
updateMap :: (Ord k) => k -> (Maybe v -> Maybe v) -> TSMap k v -> IO ()
updateMap k f (TSMap t) = atomically $ modifyTVar' t (Map.alter f k)

-- Modifies the value associated with a key using the provided function.
modifyMap :: (Ord k) => k -> (v -> v) -> TSMap k v -> IO ()
modifyMap k f m = updateMap k (fmap f) m

-- Converts the thread-safe map to a list of key-value pairs.
toListMap :: TSMap k v -> IO [(k, v)]
toListMap (TSMap t) = atomically $ Map.toList <$> readTVar t

-- Checks if the thread-safe map is empty.
isEmptyMap :: TSMap k v -> IO Bool
isEmptyMap (TSMap t) = atomically $ Map.null <$> readTVar t

getTSMapTVar :: TSMap k v -> TVar (Map.Map k v)
getTSMapTVar (TSMap t) = t
