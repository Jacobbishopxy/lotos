-- file: Util.hs
-- author: Jacob Xie
-- date: 2024/04/12 09:40:40 Friday
-- brief:

module Lotos.Util
  ( (!?),
    either2Maybe,
    maybe2Either,
  )
where

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

either2Maybe :: Either e a -> Maybe a
either2Maybe d = case d of
  Left _ -> Nothing
  Right r -> Just r

maybe2Either :: e -> Maybe a -> Either e a
maybe2Either e d = case d of
  Nothing -> Left e
  Just r -> Right r
