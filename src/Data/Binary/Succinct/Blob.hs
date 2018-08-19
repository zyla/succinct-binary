module Data.Binary.Succinct.Blob
  ( Blob(..)
  , runPut
  -- guts
  , inspectMeta
  , inspectShape
  , inspectContent
  , inspectBlob
  ) where

import Data.Binary.Succinct.Orphans ()
import Data.Binary.Succinct.Put
import Data.Bits
import Data.ByteString as Strict
import Data.ByteString.Builder as Builder
import Data.ByteString.Lazy as Lazy
import Data.Semigroup
import qualified Data.Vector.Storable as Storable
import Data.Vector.Storable.ByteString
import Data.Word
import HaskellWorks.Data.BalancedParens.RangeMinMax as BP
import HaskellWorks.Data.RankSelect.Base.Rank0
import HaskellWorks.Data.RankSelect.CsPoppy as CsPoppy

data Blob = Blob
  { blobSize    :: Word64
  , blobMeta    :: CsPoppy
  , blobShape   :: RangeMinMax (Storable.Vector Word64)
  , blobContent :: Strict.ByteString
  } deriving Show

runPutM :: PutM a -> (a, Blob)
runPutM ma = case unPutM ma (S 0 0 0 0) of
    Result a (S i b j b') (W m s c n) -> (a, Blob 
      { blobSize = n
      , blobMeta = makeCsPoppy $ ws $ flush8 i b m
      , blobShape = mkRangeMinMax $ ws $ flush8 j b' s
      , blobContent = bs c
      })
  where
    flush :: Int -> Word8 -> Builder -> Builder
    flush 0 _ xs = xs
    flush _ b xs = xs <> word8 b

    flush8 :: Int -> Word8 -> Builder -> Builder
    flush8 r k d = flush r k d <> stimes (7 :: Int) (word8 0)

    trim8 :: Strict.ByteString -> Strict.ByteString
    trim8 b = Strict.take (Strict.length b .&. complement 7) b

    bs :: Builder -> Strict.ByteString
    bs = Lazy.toStrict . Builder.toLazyByteString

    ws :: Builder -> Storable.Vector Word64
    ws = byteStringToVector . trim8 . bs
  
runPut :: Put -> Blob
runPut = snd . runPutM

rank1_ :: Rank1 v => v -> Word64 -> Word64
rank1_ s i
  | i <= 0 = 0
  | otherwise = rank1 s (fromIntegral i)

rank0_ :: Rank0 v => v -> Word64 -> Word64
rank0_ s i
  | i <= 0 = 0
  | otherwise = rank0 s (fromIntegral i)

access :: Rank1 v => v -> Word64 -> Bool
access s i = toEnum $ fromIntegral $ rank1_ s i - rank1_ s (i-1)

-- Print out a string of S's and D's, corresponding to Shape or Data, from the meta index
inspectMeta :: Blob -> String
inspectMeta (Blob n m _ _) = do
  i <- [1..n]
  case access m i of
    True -> "S"
    False -> "D"

-- Print out the balanced parentheses representation of our shape index
inspectShape :: Blob -> String
inspectShape (Blob n m s _) = do
  i <- [1..rank1 m n]
  case access s i of
    True  -> "("
    False -> ")"

-- Print out our raw content buffer
inspectContent :: Blob -> String
inspectContent (Blob _ _ _ c) = show c

-- Print out a representation of the entire blob, interleaving shape and content
inspectBlob :: Blob -> String
inspectBlob (Blob n m s c) = do
  i <- [1..n]
  case access m i of
    True  -> case access s $ fromIntegral $ rank1_ m i of
      True  -> "("
      False -> ")"
    False -> "{" ++ show (Strict.index c $ (fromIntegral $ rank0_ m i) - 1) ++ "}"
