-- Copyright 2018 Google LLC
--
-- Licensed under the Apache License, Version 2.0 (the "License"); you may not
-- use this file except in compliance with the License. You may obtain a copy of
-- the License at
--
--     https://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
-- WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
-- License for the specific language governing permissions and limitations under
-- the License.

module Data.Hmac
  ( SecretKey(SecretKey)
  , Hmac
  , hmac
  ) where

import Data.ByteString (ByteString)
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Lazy as ByteString.Lazy
import qualified Data.ByteString.Unsafe as ByteString
import Foreign (Storable(peek), alloca, allocaArray, withForeignPtr)
import Foreign.Marshal.Unsafe (unsafeLocalState)
import Unsafe.Coerce (unsafeCoerce)

import Data.Digest.Internal (Algorithm(Algorithm), Digest(Digest))
import Foreign.Ptr.ConstantTimeEquals (constantTimeEquals)
import Internal.Base
import Internal.Digest
import Internal.Hmac

type LazyByteString = ByteString.Lazy.ByteString

-- | A secret key used as input to a cipher or HMAC. Equality comparisons on
-- this type are variable-time.
newtype SecretKey = SecretKey ByteString
  deriving (Eq, Ord, Show)

-- | A hash-based message authentication code. Equality comparisons on this type
-- are constant-time.
newtype Hmac = Hmac ByteString

instance Eq Hmac where
  (Hmac a) == (Hmac b) =
    unsafeLocalState $
      ByteString.unsafeUseAsCStringLen a $ \(a', size) ->
        ByteString.unsafeUseAsCStringLen b $ \(b', _) ->
          constantTimeEquals a' b' size

instance Show Hmac where
  show (Hmac m) = show (Digest m)

-- | Creates an HMAC according to the given 'Algorithm'.
hmac :: Algorithm -> SecretKey -> LazyByteString -> Hmac
hmac (Algorithm md) (SecretKey key) bytes =
  unsafeLocalState $ do
    ctxFP <- mallocHmacCtx
    withForeignPtr ctxFP $ \ctx -> do
      ByteString.unsafeUseAsCStringLen key $ \(keyBytes, keySize) ->
        hmacInitEx ctx keyBytes (fromIntegral keySize) md noEngine
      mapM_ (updateBytes ctx) (ByteString.Lazy.toChunks bytes)
      m <-
        allocaArray evpMaxMdSize $ \hmacOut ->
          alloca $ \pOutSize -> do
            hmacFinal ctx hmacOut pOutSize
            outSize <- fromIntegral <$> peek pOutSize
            -- As in 'Data.Digest.Internal', 'hmacOut' is a 'Ptr CUChar'. Have
            -- GHC reinterpret it as a 'Ptr CChar' so that it can be ingested
            -- into a 'ByteString'.
            ByteString.packCStringLen (unsafeCoerce hmacOut, outSize)
      return (Hmac m)
  where
    updateBytes ctx chunk =
      -- 'hmacUpdate' treats its @bytes@ argument as @const@, so the sharing
      -- inherent in 'ByteString.unsafeUseAsCStringLen' is fine.
      ByteString.unsafeUseAsCStringLen chunk $ \(buf, len) ->
        -- 'buf' is a 'Ptr CChar', but 'hmacUpdate' takes a 'Ptr CUChar', so we
        -- do the 'unsafeCoerce' dance yet again.
        hmacUpdate ctx (unsafeCoerce buf) (fromIntegral len)
