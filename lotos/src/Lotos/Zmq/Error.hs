-- file: Error.hs
-- author: Jacob Xie
-- date: 2025/03/13 13:41:35 Thursday
-- brief:

module Lotos.Zmq.Error
  ( ZmqError (..),
    zmqErrWrap,
    zmqUnwrap,
    zmqThrow,
    maybeToEither,
  )
where

import Control.Monad.IO.Class (liftIO)
import Data.Text qualified as Text
import Lotos.Logger
import Zmqx

data ZmqError
  = ZmqParsing Text.Text
  | ZmqErr Zmqx.Error
  deriving (Show)

zmqErrWrap :: Either Zmqx.Error a -> Either ZmqError a
zmqErrWrap (Left e) = Left $ ZmqErr e
zmqErrWrap (Right a) = Right a

zmqUnwrap :: IO (Either Zmqx.Error a) -> LotosAppMonad a
zmqUnwrap = logUnwrap logErrorR show

zmqThrow :: IO (Either Zmqx.Error a) -> LotosAppMonad a
zmqThrow action = do
  zmqErrWrap <$> liftIO action >>= \case
    Left err -> do
      logErrorR $ "zmqThrow: " <> show err
      error $ show err
    Right a -> return a

maybeToEither :: ZmqError -> Maybe a -> Either ZmqError a
maybeToEither _ (Just x) = Right x
maybeToEither err Nothing = Left err
