{-# LANGUAGE BangPatterns #-}

-- file: RingBuffer.hs
-- author: Jacob Xie
-- date: 2025/03/25 10:32:33 Tuesday
-- brief:

module Lotos.TSD.RingBuffer
  ( -- * TSRingBuffer
    TSRingBuffer,
    getBufferCapacity,
    setBufferCapacity,
    mkTSRingBuffer,
    writeBuffer,
    writeBuffer',
    getBuffer,
    getBuffer',
  )
where

import Control.Concurrent.STM
import Data.Foldable (toList)
import Data.Sequence (Seq, ViewL (..), (|>))
import Data.Sequence qualified as Seq

-- | A ring-buffer that holds up to a fixed number of log messages.
data TSRingBuffer a = TSRingBuffer
  { capacity :: !Int, -- Maximum number of log messages
    buffer :: TVar (Seq a) -- STM-protected sequence of logs
  }

getBufferCapacity :: TSRingBuffer a -> Int
getBufferCapacity = capacity

setBufferCapacity :: TSRingBuffer a -> Int -> TSRingBuffer a
setBufferCapacity rb cap = rb {capacity = cap}

-- | Create a new ring-buffer with the specified capacity.
mkTSRingBuffer :: Int -> IO (TSRingBuffer a)
mkTSRingBuffer cap = atomically $ do
  buf <- newTVar Seq.empty
  return $ TSRingBuffer cap buf

-- | Append a new log message to the ring-buffer.
-- If the buffer is full, the oldest message is dropped.
writeBuffer :: TSRingBuffer a -> a -> IO ()
writeBuffer rb msg = atomically $ do
  buf <- readTVar (buffer rb)
  let buf' =
        if Seq.length buf >= capacity rb
          then case Seq.viewl buf of
            EmptyL -> Seq.singleton msg -- Fallback: should not occur if length >= capacity
            _ :< rest -> rest |> msg
          else buf |> msg
  writeTVar (buffer rb) buf'

writeBuffer' :: TSRingBuffer a -> [a] -> IO ()
writeBuffer' rb msgs = mapM_ (writeBuffer rb) msgs

-- | Retrieve all log messages in order from oldest to newest.
getBuffer :: TSRingBuffer a -> IO [a]
getBuffer rb = atomically $ do
  buf <- readTVar (buffer rb)
  return $ toList buf

getBuffer' :: TSRingBuffer a -> Int -> IO [a]
getBuffer' rb n = atomically $ do
  buf <- readTVar (buffer rb)
  return $ toList $ Seq.take n buf
