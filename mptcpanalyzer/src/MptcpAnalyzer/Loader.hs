{-|
Module      : MptcpAnalyzer.Loader
Description : Load pcap/csv into a @Frame@
Maintainer  : matt
License     : GPL-3
-}
module MptcpAnalyzer.Loader (
  loadPcapIntoFrame
  , loadPcapIntoFrameNoCache
  , buildAFrameFromStreamIdTcp
  , buildAFrameFromStreamIdMptcp
  )
where
import MptcpAnalyzer.Cache
import MptcpAnalyzer.Frame
import MptcpAnalyzer.Pcap
import MptcpAnalyzer.Stream
import MptcpAnalyzer.Types
import MptcpAnalyzer.Utils.Text
import Tshark.Main

import Control.Monad.Trans (liftIO)
import Distribution.Simple.Utils (TempFileOptions(..), withTempFileEx)
import Frames
import Frames.CSV
import qualified Frames.InCore
import Net.Mptcp
import Net.Tcp
import Polysemy (Embed, Members, Sem)
import Polysemy.State as P
import Prelude hiding (log)
import System.Exit (ExitCode(..))

import qualified Data.Vinyl as V
import qualified Data.Vinyl.Class.Method as V
import GHC.IO.Handle (hClose)
import Polysemy.Log (Log)
import qualified Polysemy.Log as Log

loadPcapIntoFrameNoCache :: (
    Frames.InCore.RecVec a
    , Frames.CSV.ReadRec a
    , ColumnHeaders a
   )
    => TsharkParams
    -> FilePath
    -> IO (Either String (FrameRec a))
loadPcapIntoFrameNoCache params path = do
  res <- liftIO $ withTempFileEx opts "/tmp" "mptcp.csv" $ \tmpPath handle -> do
    res <- exportToCsv params path handle
    case res of
      (ExitSuccess, _ ) -> do
        -- we have to close the handle else loadRows can't access the file !
        hClose handle
        loaded <- loadRows tmpPath
        return $ Right loaded
      (exitCode, stdErr) -> return $ Left $ "Error happened " ++ show exitCode ++ "\n" ++ show stdErr
  return res
  where
    opts :: TempFileOptions
    opts = TempFileOptions False

-- TODO return an Either or Maybe ?
-- return an either instead
loadPcapIntoFrame ::
    (Frames.InCore.RecVec a
    , Frames.CSV.ReadRec a
    , ColumnHeaders a
    , V.RecMapMethod Show ElField a, V.RecordToList a
    , Members [Log, Cache, Embed IO ] m)
    => TsharkParams
    -> FilePath
    -> Sem m (Either String (FrameRec a))
loadPcapIntoFrame params path = do
    Log.info $ "Start loading pcap " <> tshow path
    x <- getCache cacheId
    case x of
      Right frame -> do
          Log.debug $ tshow cacheId <> " in cache"
          return $ Right frame
      Left err -> do
          Log.debug $ "cache miss: " <> tshow  err
          Log.debug "Calling tshark"
          (tempPath , exitCode, stdErr) <- liftIO $ do
            withTempFileEx opts "/tmp" "mptcp.csv" $ \tmpPath handle -> do
                (exitCode, herr) <- exportToCsv params path handle
                return (tmpPath, exitCode, herr)

          if exitCode == ExitSuccess
              then do
                Log.debug $ "exported to file " <> tshow tempPath
                frame <- liftIO $ loadRows tempPath
                Log.debug $ "Number of rows after loading " <> tshow (frameLength frame)
                cacheRes <- putCache cacheId frame
                -- use ifThenElse instead
                if cacheRes then
                  Log.info "Saved into cache"
                else
                  pure ()
                return $ Right frame
              else do
                Log.info $ "Error happened: " <> tshow exitCode
                Log.info $ tshow stdErr
                return $ Left stdErr

    where
      cacheId = CacheId [path] "" "csv"
      opts :: TempFileOptions
      opts = TempFileOptions True


-- buildTcpFrameFromFrame
-- \ Build a frame with only packets belonging to @streamId@
buildAFrameFromStreamIdTcp :: (Members [Log, Cache, Embed IO ] m)
    => TsharkParams
    -> FilePath
    -> StreamId Tcp
    -> Sem m (Either String (FrameFiltered TcpConnection Packet))
buildAFrameFromStreamIdTcp params pcapFilename streamId = do
    res <- loadPcapIntoFrame params pcapFilename
    return $ case res of
      Left err -> Left err
      Right frame -> buildTcpConnectionFromStreamId frame streamId

buildAFrameFromStreamIdMptcp :: (Members [Log, Cache, Embed IO ] m)
    => TsharkParams
    -> FilePath
    -> StreamId Mptcp
    -> Sem m (Either String (FrameFiltered MptcpConnection Packet))
buildAFrameFromStreamIdMptcp params pcapFilename streamId = do
  Log.debug  ("Building frame for mptcp stream " <> tshow streamId)
  res <- loadPcapIntoFrame params pcapFilename
  return $ case res of
    Left err -> Left err
    Right frame -> buildMptcpConnectionFromStreamId frame streamId
