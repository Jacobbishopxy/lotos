-- file: Queue.hs
-- author: Jacob Xie
-- date: 2025/03/25 10:30:38 Tuesday
-- brief:

module Lotos.TSD.Queue
  ( -- * que
    TSQueue,
    peekQueue,
    peekQueue',
    mkTSQueue,
    enqueueTS,
    enqueueTSs,
    dequeueTS,
    dequeueN,
    dequeueN',
    readQueue,
    readQueue',
    isEmptyQueue,
  )
where

import Control.Concurrent.STM
import Data.Foldable (toList)
import Data.Sequence qualified as Seq

----------------------------------------------------------------------------------------------------
-- Queue
----------------------------------------------------------------------------------------------------

-- A thread-safe queue implemented using a TVar containing a Sequence.
newtype TSQueue a = TSQueue (TVar (Seq.Seq a))

-- Creates a new empty thread-safe queue.
mkTSQueue :: IO (TSQueue a)
mkTSQueue = TSQueue <$> newTVarIO Seq.empty

-- Peek at the first N elements of the queue (without modifying it).
peekQueue :: Int -> TSQueue a -> IO (Seq.Seq a)
peekQueue n (TSQueue t) = atomically $ Seq.take n <$> readTVar t

-- Peek at the first N elements of the queue (without modifying it).
peekQueue' :: Int -> TSQueue a -> IO [a]
peekQueue' n (TSQueue t) = atomically $ toList . Seq.take n <$> readTVar t

-- Enqueues an element into the thread-safe queue.
enqueueTS :: a -> TSQueue a -> IO ()
enqueueTS x (TSQueue t) = atomically $ modifyTVar' t (\s -> s Seq.|> x)

-- Enqueues a list of elements into the thread-safe queue.
enqueueTSs :: [a] -> TSQueue a -> IO ()
enqueueTSs xs (TSQueue t) = atomically $ modifyTVar' t (\s -> s Seq.>< Seq.fromList xs)

-- Dequeues an element from the thread-safe queue. Returns Nothing if the queue is empty.
dequeueTS :: TSQueue a -> IO (Maybe a)
dequeueTS (TSQueue t) = atomically $ do
  s <- readTVar t
  case Seq.viewl s of
    Seq.EmptyL -> return Nothing
    x Seq.:< xs -> do
      writeTVar t xs
      return (Just x)

-- Dequeues the first N elements from the thread-safe queue.
dequeueN :: Int -> TSQueue a -> IO (Seq.Seq a)
dequeueN n (TSQueue t) = atomically $ do
  s <- readTVar t
  let (taken, remaining) = Seq.splitAt n s
  writeTVar t remaining
  return taken

-- Dequeues the first N elements from the thread-safe queue.
dequeueN' :: Int -> TSQueue a -> IO [a]
dequeueN' n (TSQueue t) = atomically $ do
  s <- readTVar t
  let (taken, remaining) = Seq.splitAt n s
  writeTVar t remaining
  return (toList taken)

-- Reads the entire content of the queue without modifying it.
readQueue :: TSQueue a -> IO (Seq.Seq a)
readQueue (TSQueue t) = atomically $ readTVar t

-- Reads the entire content of the queue without modifying it.
readQueue' :: TSQueue a -> IO [a]
readQueue' (TSQueue t) = atomically $ toList <$> readTVar t

-- Checks if the thread-safe queue is empty.
isEmptyQueue :: TSQueue a -> IO Bool
isEmptyQueue (TSQueue t) = atomically $ Seq.null <$> readTVar t
