-- file: Util.hs
-- author: Jacob Xie
-- date: 2024/04/12 09:40:40 Friday
-- brief:

module Lotos.Util
  ( either2Maybe,
    maybe2Either,
    availableCores,
  )
where

import GHC.Conc (numCapabilities)

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
