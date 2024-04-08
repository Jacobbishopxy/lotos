-- file: Lotos.hs
-- author: Jacob Xie
-- date: 2024/04/07 21:13:13 Sunday
-- brief:

module Lotos
  ( module Lotos.Csv,
    module Lotos.Airflow.Cron,
    module Lotos.Airflow.Conf,
    (!?),
  )
where

import Lotos.Airflow.Conf
import Lotos.Airflow.Cron
import Lotos.Csv

-- safe `!!`
(!?) :: [a] -> Int -> Maybe a
{-# INLINEABLE (!?) #-}
xs !? n
  | n < 0 = Nothing
  | otherwise =
      foldr
        ( \x r k -> case k of
            0 -> Just x
            _ -> r (k - 1)
        )
        (const Nothing)
        xs
        n
