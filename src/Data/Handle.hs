{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}

module Data.Handle
  ( Handle (..)
  , getHandle
  , stdin
  , stdout
  , stderr
  , readBlobsFromHandle
  , readPathsFromHandle
  , readBlobPairsFromHandle
  , readFromHandle
  , openFileForReading
  , InvalidProtoException (..)
  ) where

import           Control.Exception (Exception, throw)
import           Control.Lens
import           Control.Monad.IO.Class
import qualified Data.ByteString as BL
import qualified Data.ByteString.Char8 as BLC
import           Data.ProtoLens
import qualified Data.Text as Text
import qualified Proto.Semantic as Proto
import           Proto.Semantic_Fields (blobs, content, language, path)
import qualified Source.Language as Language
import qualified Source.Source as Source
import qualified System.IO as IO
import qualified System.Path as Path

import Data.Blob hiding (blobs)

data Handle mode where
  ReadHandle  :: IO.Handle -> Handle 'IO.ReadMode
  WriteHandle :: IO.Handle -> Handle 'IO.WriteMode

deriving instance Eq   (Handle mode)
deriving instance Show (Handle mode)

getHandle :: Handle mode -> IO.Handle
getHandle (ReadHandle  handle) = handle
getHandle (WriteHandle handle) = handle

stdin :: Handle 'IO.ReadMode
stdin = ReadHandle IO.stdin

stdout :: Handle 'IO.WriteMode
stdout = WriteHandle IO.stdout

stderr :: Handle 'IO.WriteMode
stderr = WriteHandle IO.stderr

openFileForReading :: FilePath -> IO (Handle 'IO.ReadMode)
openFileForReading path = ReadHandle <$> IO.openFile path IO.ReadMode

-- | Read JSON encoded blobs from a handle.
readBlobsFromHandle :: forall m. MonadIO m => Handle 'IO.ReadMode -> m [Blob]
readBlobsFromHandle handle = do
  request <- readFromHandle @Proto.StackGraphRequest handle
  pure (fromProto <$> request^.blobs)

-- | Read line delimited paths from a handle
readPathsFromHandle :: MonadIO m => Handle 'IO.ReadMode -> m [FilePath]
readPathsFromHandle (ReadHandle h) = liftIO $ fmap BLC.unpack . BLC.lines <$> BL.hGetContents h

-- | Read JSON encoded blob pairs from a handle.
readBlobPairsFromHandle :: forall m. MonadIO m => Handle 'IO.ReadMode -> m [BlobPair]
readBlobPairsFromHandle = undefined
-- do
-- request <- readFromHandle @Proto.DiffTreeRequest @m
-- pure (fromProto <$> request^.blobs)

newtype InvalidProtoException = InvalidProtoException String
  deriving (Eq, Show, Exception)

-- | Read JSON-encoded data from a 'Handle'. Throws
-- 'InvalidJSONException' on parse failure.
readFromHandle :: forall a m. (Message a, MonadIO m) => Handle 'IO.ReadMode -> m a
readFromHandle (ReadHandle h) = do
  input <- liftIO $ BL.hGetContents h
  case decodeMessage input of
    Left e  -> throw (InvalidProtoException e)
    Right d -> pure d


fromProto :: Proto.Blob -> Blob
fromProto blob =
  let
    lang = Language.textToLanguage (blob^.language)
    Right path' = Path.parse (Text.unpack $ blob^.path)
    lang' = if Language.knownLanguage lang then lang else Language.forPath path'
  in
    fromSource (path' :: Path.AbsRelFile) lang' (Source.fromText $ blob^.content)
