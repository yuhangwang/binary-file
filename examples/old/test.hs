{-# LANGUAGE QuasiQuotes #-}

import QuoteBinaryStructure
import System.Environment
import Data.Bits
import System.IO

[binary|

Bitmap

2: "BM"
4: fileSize
2: 0
2: 0
4: offset
4: 40
4: bitmapWidth
4: bitmapHeight
2: 1
2: bitsPerPixel
4: compressionMethod
4: imageSize
4: horizontalResolution
4: verticalResolution
4: numberOfColors
4: importantColors
4[numberOfColors]: colors
bitsPerPixel/8[imageSize*8/bitsPerPixel]: image
9<String>: authorFirst
4<String>: authorSecond

|]

main = do
	[fn] <- getArgs
	cnt <- readBinaryFile fn
	let bmp = readBitmap cnt
	print $ colors $ readBitmap cnt
--	print $ length out
	print $ authorFirst bmp
	print $ authorSecond bmp
	let out = writeBitmap bmp { authorFirst = "Yoshikuni", authorSecond = "Jujo" }
	writeBinaryFile "out.bmp" out

out :: IO Bitmap
out = do
	cnt <- readBinaryFile "out.bmp" -- "test.bmp"
	return $ readBitmap cnt

test :: IO Bitmap
test = do
	cnt <- readBinaryFile "test.bmp"
	return $ readBitmap cnt

toRGB :: Int -> (Int, Int, Int)
toRGB rgb = let
	b = rgb .&. 0xff
	g = shiftR rgb 8 .&. 0xff
	r = shiftR rgb 16 in
	(r, g, b)

readBinaryFile :: FilePath -> IO String
readBinaryFile path = openBinaryFile path ReadMode >>= hGetContents

writeBinaryFile :: FilePath -> String -> IO ()
writeBinaryFile path str = do
	h <- openBinaryFile path WriteMode
	hPutStr h str
	hClose h
