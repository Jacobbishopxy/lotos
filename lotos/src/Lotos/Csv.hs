-- file: Csv.hs
-- author: Jacob Xie
-- date: 2024/04/07 22:18:31 Sunday
-- brief:

module Lotos.Csv
  ( CsvResult,
    readCsv,
  )
where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BSL
import Data.Csv
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Encoding.Error as TE
import qualified Data.Vector as Vec
import qualified System.IO as SIO

type CsvResult a = Either String (Header, Vec.Vector a)

readCsv :: (FromNamedRecord a) => FilePath -> IO (CsvResult a)
readCsv file = do
  h <- SIO.openFile file SIO.ReadMode
  b <- BS.hGetContents h

  let decodedText = TE.decodeUtf8With TE.lenientDecode b

  let csvData = decodeByName (BSL.fromStrict $ TE.encodeUtf8 decodedText)

  return csvData
