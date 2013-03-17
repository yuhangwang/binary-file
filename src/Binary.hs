module Binary (
	readBinaryFile,
	writeBinaryFile,
	binary
 ) where

import QuoteBinaryStructure
import System.IO

readBinaryFile :: FilePath -> IO String
readBinaryFile path = openBinaryFile path ReadMode >>= hGetContents

writeBinaryFile :: FilePath -> String -> IO ()
writeBinaryFile path str = do
	h <- openBinaryFile path WriteMode
	hPutStr h str
	hClose h
