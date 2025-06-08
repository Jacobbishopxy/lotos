-- file: Util.hs
-- author: Jacob Xie
-- date: 2024/04/12 09:40:40 Friday
-- brief:

module Lotos.Util
  ( either2Maybe,
    maybe2Either,
    availableCores,
    readJsonConfig,
  )
where

import GHC.Conc (numCapabilities)
import Data.Aeson qualified as Aeson
import qualified Data.ByteString.Lazy as BL

either2Maybe :: Either e a -> Maybe a
either2Maybe d = case d of
  Left _ -> Nothing
  Right r -> Just r

maybe2Either :: e -> Maybe a -> Either e a
maybe2Either e d = case d of
  Nothing -> Left e
  Just r -> Right r

availableCores :: IO ()
availableCores = putStrLn $ "Available cores: " ++ show numCapabilities

readJsonConfig :: Aeson.FromJSON a  =>  FilePath -> IO a
readJsonConfig fp = do
  content <- BL.readFile fp
  case Aeson.eitherDecode content of
    Left err -> error $ "Failed to parse JSON: " ++ err
    Right d -> return d
