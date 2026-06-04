{-# LANGUAGE BlockArguments #-}

-- file: ZmqXT.hs
-- author: Jacob Xie
-- date: 2025/05/05 07:12:28 Monday
-- brief: zmq cross threads test

module Main where

import Control.Concurrent
import Control.Exception
import Control.Monad
import Control.Monad.RWS
import Data.ByteString.Char8 qualified as C
import Lotos.Logger
import Zmqx
import Zmqx.Monad qualified as ZmqxM
import Zmqx.Sub

unwrap :: IO (Either Zmqx.Error a) -> IO a
unwrap action =
  action >>= \case
    Left err -> throwIO err
    Right value -> pure value

unwrapApp :: LotosApp (Either Zmqx.Error a) -> LotosApp a
unwrapApp action =
  action >>= \case
    Left err -> liftIO $ throwIO err
    Right value -> pure value

setupSubAndPair :: LotosApp (Zmqx.Sub, Zmqx.Pair)
setupSubAndPair = do
    tid' <- liftIO myThreadId
    logApp INFO $ "$$$ 2 > " <> show tid'
    -- declare in a separate thread
    sub <- unwrapApp $ ZmqxM.open (Zmqx.name "sub")
    liftIO $ unwrap $ Zmqx.Sub.subscribe sub (C.pack "")
    unwrapApp $ ZmqxM.connect sub "tcp://127.0.0.1:5555"

    pair2 <- unwrapApp $ ZmqxM.open $ Zmqx.name "pair2"
    unwrapApp $ ZmqxM.connect pair2 "inproc://pair-test"

    return (sub, pair2)

receiveLoop :: Zmqx.Sub -> Zmqx.Pair -> LotosApp ()
receiveLoop sub pair2 = do
  tid <- liftIO myThreadId
  logApp INFO $ "$$$ 3 > " <> show tid
  logApp INFO "Waiting for messages..."

  result <- ZmqxM.receivesFor sub 2000
  case result of
    Right (Just msgs) -> do
      logApp INFO $ "Received: " ++ show msgs
      _ <- unwrapApp $ ZmqxM.sends pair2 msgs
      receiveLoop sub pair2
    Right Nothing -> do
      logApp INFO "Timeout occurred"
      receiveLoop sub pair2
    Left err -> do
      logApp INFO $ "Error: " ++ show err
      receiveLoop sub pair2

publisherLoop :: Zmqx.Pub -> LotosApp ()
publisherLoop pub = void $ forever do
    unwrapApp $ ZmqxM.send pub (C.pack "Hello from PUB")
    liftIO $ threadDelay $ 5 * 1_000_000  -- 5s between publishes

receivePairMessages :: Zmqx.Pair -> LotosApp ()
receivePairMessages pair1 = void $ forever do
    result <- ZmqxM.receives pair1
    case result of
        Right msgs -> logApp INFO $ "Received from pair1: " ++ show msgs
        Left err -> logApp INFO $ "Error: " ++ show err

main :: IO ()
main = do
  logConfig <- initConsoleLogger DEBUG

  _ <- runZmqApp logConfig do
    tid <- liftIO myThreadId
    logApp INFO $ "$$$ 1 > " <> show tid
    pair1 <- unwrapApp $ ZmqxM.open $ Zmqx.name "pair1"
    unwrapApp $ ZmqxM.bind pair1 "inproc://pair-test"

    t1 <- forkApp do
      (sub, pair2) <- setupSubAndPair
      receiveLoop sub pair2

    logApp INFO $ "t1: " <> show t1

    t2 <- forkApp do
      pub <- unwrapApp $ ZmqxM.open $ Zmqx.name "pub"
      unwrapApp $ ZmqxM.bind pub "tcp://127.0.0.1:5555"
      publisherLoop pub
    logApp INFO $ "t2: " <> show t2

    -- receive messages from pair2
    receivePairMessages pair1

  return ()
