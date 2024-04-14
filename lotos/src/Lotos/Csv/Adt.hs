-- file: Adt.hs
-- author: Jacob Xie
-- date: 2024/04/14 14:20:33 Sunday
-- brief:

module Lotos.Csv.Adt
  ( module Lotos.Csv.Adt,
  )
where

import qualified Data.ByteString as B
import qualified Data.HashMap.Strict as HM
import Data.Vector

-- | CSV data represented as a Haskell vector of vector of
-- bytestrings.
type Csv = Vector Record

-- | A record corresponds to a single line in a CSV file.
type Record = Vector Field

-- | The header corresponds to the first line a CSV file. Not all CSV
-- files have a header.
type Header = Vector Name

-- | A header has one or more names, describing the data in the column
-- following the name.
type Name = B.ByteString

-- | A record corresponds to a single line in a CSV file, indexed by
-- the column name rather than the column index.
type NamedRecord = HM.HashMap B.ByteString B.ByteString

-- | A single field within a record.
type Field = B.ByteString
