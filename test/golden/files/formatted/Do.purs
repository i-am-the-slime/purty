module Do where

foo = do
  let
    v = 0
    w = 12
  x <- pure 1
  y <- pure 2
  longName <- pure 3
  pure $ w + x + y + longName
