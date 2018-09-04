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

{-# LANGUAGE OverloadedStrings #-}

module Data.HMACTests (tests) where

import Control.Monad (unless)
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Lazy as ByteString.Lazy
import qualified Data.ByteString.Lazy.Char8 as ByteString.Lazy.Char8
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertFailure, testCase)

import Data.Digest (md5, sha1, sha224, sha256, sha384, sha512)
import Data.HMAC (Error, SecretKey(SecretKey), hmac)

type LazyByteString = ByteString.Lazy.ByteString

tests :: TestTree
tests = testGroup "Data.HMAC"
  [ testRFC2202
  , testFips198
  , testRFC4231
  ]

tableTestCase ::
     (SecretKey -> LazyByteString -> Either [Error] String)
  -> (SecretKey, LazyByteString, String)
  -> TestTree
tableTestCase f (key, input, output) =
  testCase (abbreviate input) (f key input `isRightAndHolds` output)

abbreviate :: LazyByteString -> String
abbreviate input =
  let (x, y) = splitAt 12 (show input) in
  x ++ (if null y then "" else "...") ++ "\""

-- | Tests from RFC 2202.
testRFC2202 = testGroup "RFC 2202" [testMd5, testSha1]
  where
    testMd5 = testGroup "MD5" $
      map (tableTestCase hmacMd5)
        [ ( SecretKey (ByteString.replicate 16 0x0b)
          , "Hi There"
          , "9294727a3638bb1c13f48ef8158bfc9d")
        , ( SecretKey "Jefe"
          , "what do ya want for nothing?"
          , "750c783e6ab0b503eaa86e310a5db738")
        , ( SecretKey (ByteString.replicate 16 0xaa)
          , ByteString.Lazy.replicate 50 0xdd
          , "56be34521d144c88dbb8c733f0e8b3f6")
        , ( SecretKey (ByteString.pack [0x01 .. 0x19])
          , ByteString.Lazy.replicate 50 0xcd
          , "697eaf0aca3a3aea3a75164746ffaa79")
        , ( SecretKey (ByteString.replicate 16 0x0c)
          , "Test With Truncation"
          , "56461ef2342edc00f9bab995690efd4c")
        , ( SecretKey (ByteString.replicate 80 0xaa)
          , "Test Using Larger Than Block-Size Key - Hash Key First"
          , "6b1ab7fe4bd7bf8f0b62e6ce61b9d0cd")
        , ( SecretKey (ByteString.replicate 80 0xaa)
          , "Test Using Larger Than Block-Size Key and Larger Than One Block-Size Data"
          , "6f630fad67cda0ee1fb1f562db3aa53e")
        ]
    testSha1 = testGroup "SHA-1" $
      map (tableTestCase hmacSha1)
        [ ( SecretKey (ByteString.replicate 20 0x0b)
          , "Hi There"
          , "b617318655057264e28bc0b6fb378c8ef146be00")
        , ( SecretKey "Jefe"
          , "what do ya want for nothing?"
          , "effcdf6ae5eb2fa2d27416d5f184df9c259a7c79")
        , ( SecretKey (ByteString.replicate 20 0xaa)
          , ByteString.Lazy.replicate 50 0xdd
          , "125d7342b9ac11cd91a39af48aa17b4f63f175d3")
        , ( SecretKey (ByteString.pack [0x01 .. 0x19])
          , ByteString.Lazy.replicate 50 0xcd
          , "4c9007f4026250c6bc8414f9bf50c86c2d7235da")
        , ( SecretKey (ByteString.replicate 20 0x0c)
          , "Test With Truncation"
          , "4c1a03424b55e07fe7f27be1d58bb9324a9a5a04")
        , ( SecretKey (ByteString.replicate 80 0xaa)
          , "Test Using Larger Than Block-Size Key - Hash Key First"
          , "aa4ae5e15272d00e95705637ce8a3b55ed402112")
        , ( SecretKey (ByteString.replicate 80 0xaa)
          , "Test Using Larger Than Block-Size Key and Larger Than One Block-Size Data"
          , "e8e99d0f45237d786d6bbaa7965c7808bbff1a91")
        ]

-- | Tests from FIPS 198.
testFips198 = testGroup "FIPS 198" $
  map (tableTestCase hmacSha1)
    [ ( SecretKey (ByteString.pack [0 .. 0x3f])
      , "Sample #1"
      , "4f4ca3d5d68ba7cc0a1208c9c61e9c5da0403c0a")
    , ( SecretKey (ByteString.pack [0x30 .. 0x43])
      , "Sample #2"
      , "0922d3405faa3d194f82a45830737d5cc6c75d24")
    , ( SecretKey (ByteString.pack [0x50 .. 0xb3])
      , "Sample #3"
      , "bcf41eab8bb2d802f3d05caf7cb092ecf8d1a3aa")
    ]
    ++ [truncatedFips198Test]

truncatedFips198Test =
  let input = "Sample #4" :: String
      key = SecretKey (ByteString.pack [0x70 .. 0xa0])
      output = "9ea886efe268dbecce420c75" :: String
  in testCase
       (show input)
       ((take 24 <$> hmacSha1 key (ByteString.Lazy.Char8.pack input)) `isRightAndHolds` output)

rfc4231TestCase ::
     (SecretKey, LazyByteString, String, String, String, String) -> TestTree
rfc4231TestCase (key, input, sha224Output, sha256Output, sha384Output, sha512Output) =
  testGroup (abbreviate input)
    [ testCase "SHA-224" (hmacSha224 key input `isRightAndHolds` sha224Output)
    , testCase "SHA-256" (hmacSha256 key input `isRightAndHolds` sha256Output)
    , testCase "SHA-384" (hmacSha384 key input `isRightAndHolds` sha384Output)
    , testCase "SHA-512" (hmacSha512 key input `isRightAndHolds` sha512Output)
    ]

-- | Tests from RFC 4231.
testRFC4231 = testGroup "RFC 4231" $
  map rfc4231TestCase
    [ ( SecretKey (ByteString.replicate 20 0x0b)
      , "Hi There"
      , "896fb1128abbdf196832107cd49df33f47b4b1169912ba4f53684b22"
      , "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
      , "afd03944d84895626b0825f4ab46907f15f9dadbe4101ec682aa034c7cebc59cfaea9ea9076ede7f4af152e8b2fa9cb6"
      , "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cdedaa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854")
    , ( SecretKey "Jefe"
      , "what do ya want for nothing?"
      , "a30e01098bc6dbbf45690f3a7e9e6d0f8bbea2a39e6148008fd05e44"
      , "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
      , "af45d2e376484031617f78d2b58a6b1b9c7ef464f5a01b47e42ec3736322445e8e2240ca5e69e2c78b3239ecfab21649"
      , "164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737")
    , ( SecretKey (ByteString.replicate 20 0xaa)
      , ByteString.Lazy.replicate 50 0xdd
      , "7fb3cb3588c6c1f6ffa9694d7d6ad2649365b0c1f65d69d1ec8333ea"
      , "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe"
      , "88062608d3e6ad8a0aa2ace014c8a86f0aa635d947ac9febe83ef4e55966144b2a5ab39dc13814b94e3ab6e101a34f27"
      , "fa73b0089d56a284efb0f0756c890be9b1b5dbdd8ee81a3655f83e33b2279d39bf3e848279a722c806b485a47e67c807b946a337bee8942674278859e13292fb")
    , ( SecretKey (ByteString.pack [0x01 .. 0x19])
      , ByteString.Lazy.replicate 50 0xcd
      , "6c11506874013cac6a2abc1bb382627cec6a90d86efc012de7afec5a"
      , "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b"
      , "3e8a69b7783c25851933ab6290af6ca77a9981480850009cc5577c6e1f573b4e6801dd23c4a7d679ccf8a386c674cffb"
      , "b0ba465637458c6990e5a8c5f61d4af7e576d97ff94b872de76f8050361ee3dba91ca5c11aa25eb4d679275cc5788063a5f19741120c4f2de2adebeb10a298dd")
    , ( SecretKey (ByteString.replicate 131 0xaa)
      , "Test Using Larger Than Block-Size Key - Hash Key First"
      , "95e9a0db962095adaebe9b2d6f0dbce2d499f112f2d2b7273fa6870e"
      , "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"
      , "4ece084485813e9088d2c63a041bc5b44f9ef1012a2b588f3cd11f05033ac4c60c2ef6ab4030fe8296248df163f44952"
      , "80b24263c7c1a3ebb71493c1dd7be8b49b46d1f41b4aeec1121b013783f8f3526b56d037e05f2598bd0fd2215d6a1e5295e64f73f63f0aec8b915a985d786598")
    , ( SecretKey (ByteString.replicate 131 0xaa)
      , "This is a test using a larger than block-size key and a larger than block-size data. The key needs to be hashed before being used by the HMAC algorithm."
      , "3a854166ac5d9f023f54d517d0b39dbd946770db9c2b95c9f6f565d1"
      , "9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2"
      , "6617178e941f020d351e2f254e8fd32c602420feb0b8fb9adccebb82461e99c5a678cc31e799176d3860e6110c46523e"
      , "e37b6a775dc87dbaa4dfa9f96e5e3ffddebd71f8867289865df5a32d20cdc944b6022cac3c4982b10d5eeb55c3e4de15134676fb6de0446065c97440fa8c6a58")
    ]
    ++ [truncatedRFC4231Test]

truncatedRFC4231Test =
  let key = SecretKey (ByteString.replicate 20 0x0c)
      input = "Test With Truncation" :: LazyByteString
      t f = take 32 <$> f key input :: Either [Error] String
  in testGroup (abbreviate input)
       [ testCase "SHA-224" (t hmacSha224 `isRightAndHolds` "0e2aea68a90c8d37c988bcdb9fca6fa8")
       , testCase "SHA-256" (t hmacSha256 `isRightAndHolds` "a3b6167473100ee06e0c796c2955552b")
       , testCase "SHA-384" (t hmacSha384 `isRightAndHolds` "3abf34c3503b2a23a46efc619baef897")
       , testCase "SHA-512" (t hmacSha512 `isRightAndHolds` "415fad6271580a531d4179bc891d87a6")
       ]

hmacMd5    key bytes = show <$> hmac md5 key bytes
hmacSha1   key bytes = show <$> hmac sha1 key bytes
hmacSha224 key bytes = show <$> hmac sha224 key bytes
hmacSha256 key bytes = show <$> hmac sha256 key bytes
hmacSha384 key bytes = show <$> hmac sha384 key bytes
hmacSha512 key bytes = show <$> hmac sha512 key bytes

isRightAndHolds :: (Eq a, Show a, Show e) => Either e a -> a -> Assertion
actual@(Left _) `isRightAndHolds` _ =
  assertFailure ("expected: Right _\n but got: " ++ show actual)
Right actual `isRightAndHolds` expected =
  unless (expected == actual) $
    assertFailure ("expected: Right " ++ show expected ++ "\n but got: Right " ++ show actual)
