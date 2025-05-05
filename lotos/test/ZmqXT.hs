{-# LANGUAGE BlockArguments #-}

-- file: ZmqXT.hs
-- author: Jacob Xie
-- date: 2025/05/05 07:12:28 Monday
-- brief: zmq cross threads test

module Main where

import Control.Concurrent
import Control.Exception
import Control.Monad
import Data.ByteString.Char8 qualified as C
import Zmqx
import Zmqx.Pair
import Zmqx.Pub
import Zmqx.Sub

unwrap :: IO (Either Zmqx.Error a) -> IO a
unwrap action =
  action >>= \case
    Left err -> throwIO err
    Right value -> pure value

receiveLoop :: Zmqx.Sub -> Zmqx.Pair -> IO ()
receiveLoop sub pair2 = do
  putStrLn "Waiting for messages..."
  result <- Zmqx.receivesFor sub 2_000
  case result of
    Right (Just msgs) -> do
      putStrLn $ "Received: " ++ show msgs
      _ <- Zmqx.sends pair2 msgs
      receiveLoop sub pair2
    Right Nothing -> do
      putStrLn "Timeout occurred"
      receiveLoop sub pair2
    Left err -> do
      putStrLn $ "Error: " ++ show err
      receiveLoop sub pair2

main :: IO ()
main = do
  putStrLn "Testing receivesFor with SUB socket"

  Zmqx.run Zmqx.defaultOptions do
    pair1 <- unwrap $ Zmqx.Pair.open $ Zmqx.name "pair1"
    unwrap $ Zmqx.bind pair1 "inproc://pair-test"

    void $ forkIO do
      -- declare in a separate thread
      sub <- unwrap $ Zmqx.Sub.open (Zmqx.name "sub")
      unwrap $ Zmqx.Sub.subscribe sub (C.pack "")
      unwrap $ Zmqx.connect sub "tcp://127.0.0.1:5555"

      pair2 <- unwrap $ Zmqx.Pair.open $ Zmqx.name "pair2"
      unwrap $ Zmqx.connect pair2 "inproc://pair-test"

      receiveLoop sub pair2

    void $ forkIO do
      pub <- unwrap $ Zmqx.Pub.open $ Zmqx.name "pub"
      unwrap $ Zmqx.bind pub "tcp://127.0.0.1:5555"
      void $ forever do
        unwrap $ Zmqx.send pub (C.pack "Hello from PUB")
        threadDelay $ 5 * 1_000_000 -- 5s between publishes

    -- receive messages from pair2
    void $ forever do
      result <- Zmqx.receives pair1
      case result of
        Right msgs -> putStrLn $ "Received from pair1: " ++ show msgs
        Left err -> putStrLn $ "Error: " ++ show err
