{-# LANGUAGE QuasiQuotes, TypeFamilies, FlexibleInstances, ScopedTypeVariables #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

import File.Binary (binary, Field(..), Binary(..), readBinaryFile, writeBinaryFile)
import File.Binary.Instances.LittleEndian ()
import File.Binary.Instances ()
import Data.ByteString.Lazy (singleton)
import Data.Monoid (mconcat)
import Control.Applicative ((<$>))
import System.Environment (getArgs)

--------------------------------------------------------------------------------

main :: IO ()
main = do
	[inf, outf] <- getArgs
	bmp <- readBitmap inf
	putStrLn $ take 1000 (show bmp) ++ "..."
	writeBitmap outf bmp

readBitmap :: FilePath -> IO Bitmap
readBitmap fp = do
	Right (bmp, "") <- fromBinary () <$> readBinaryFile fp
	return bmp

writeBitmap :: FilePath -> Bitmap -> IO ()
writeBitmap fp bmp = do
	let Right bin = toBinary () bmp
	writeBinaryFile fp bin

instance Field (Int, Int, Int) where
	type FieldArgument (Int, Int, Int) = ()
	fromBinary _ s = do
		(b, rest) <- fromBinary 1 s
		(g, rest') <- fromBinary 1 rest
		(r, rest'') <- fromBinary 1 rest'
		return ((b, g, r), snd $ getBytes 1 rest'')
	toBinary _ (b, g, r) = do
		b' <- toBinary 1 b
		g' <- toBinary 1 g
		r' <- toBinary 1 r
		return $ mconcat [b', g', r', makeBinary $ singleton 0]

[binary|

Bitmap

deriving Show

2: "BM"
4: fileSize
2: 0
2: 0
4: offset

4: 40
4: width
4: height
2: 1
2: bits_per_pixel
4: compression
4: image_size
4: resolutionH
4: resolutionV
4: color_num
4: important_colors_num
-- ((), Just color_num){[(Int, Int, Int)]}: colors
-- ((), Just image_size){String}: image
replicate color_num (){[(Int, Int, Int)]}: colors
replicate image_size (){String}: image

|]
