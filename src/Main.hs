{-|
Description : Mptcpanalyzer
Maintainer  : matt
Stability   : testing
Portability : Linux

TemplateHaskell for Katip :(
-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE TemplateHaskell   #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE UndecidableInstances       #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE KindSignatures             #-}
{-# LANGUAGE LambdaCase             #-}

module Main where

import System.Directory
import System.IO (stdout)
import Prelude hiding (concat, init)
import Options.Applicative
-- import Control.Monad.Trans (liftIO, MonadIO)
import Control.Monad.Trans.State (State, put,
      StateT(..),
      execStateT, runStateT, evalStateT, withStateT
        )
import Control.Monad.State (MonadState, get)
import qualified Data.HashMap.Strict         as HM
import qualified Commands.Utils         as CMD

-- for noCompletion
import System.Console.Haskeline
-- import Data.List (isPrefixOf)
-- import Data.Singletons.TH
import Utils

-- import System.Console.Haskeline (MonadException)
-- import System.Console.Haskeline.MonadException
-- Repline is a wrapper (suppposedly more advanced) around haskeline
-- for now we focus on the simple usecase with repline
-- import System.Console.Repline
import Katip
import Pcap
import Cache
-- (Cache,putCache,getCache, isValid, CacheId)
import Commands.Load
-- import System.Environment.Blank   (getEnvDefault)
-- import Distribution.Simple.Utils (withTempFileEx, TempFileOptions(..))
-- import           Frames
import Pipes hiding (Proxy)
-- import qualified Pipes.Prelude as P
-- import qualified Control.Foldl as L
-- import qualified Data.Foldable as F


newtype MyStack m a = MyStack {
    unAppT :: StateT MyState m a
} deriving (Monad, Applicative, Functor
    , MonadIO
    -- , Katip, KatipContext
    , Cache
    -- , MonadReader MyState m
    , MonadState MyState
    -- , MonadException
    )

-- (MonadState MyState m, MonadIO m) =>
-- instance (Cache AppM) where
--   putCache id frame = return False
--   getCache id = Left "not implemented"
--   -- check
--   isValid = cacheCheckValidity
-- MonadBase, MonadTransControl, and MonadBaseControl aren't strictly
-- needed for this example, but they are commonly required and
-- MonadTransControl/MonadBaseControl are a pain to implement, so I've
-- included them. Note that KatipT and KatipContextT already do this work for you.
-- instance MonadBase b m => MonadBase b (MyStack m) where
--   liftBase = liftBaseDefault


-- instance MonadTransControl MyStack where
--   -- type StT MyStack a = StT (StateT Int) a
--   type StT MyStack a = StT (ReaderT Int) a

--   liftWith = defaultLiftWith MyStack unStack
--   restoreT = defaultRestoreT MyStack


-- instance MonadBaseControl b m => MonadBaseControl b (MyStack m) where
--   type StM (MyStack m) a = ComposeSt MyStack m a
--   liftBaseWith = defaultLiftBaseWith
--   restoreM = defaultRestoreM


instance (MonadIO m, MonadState MyState (MyStack m)) => Katip (MyStack m) where
  getLogEnv = do
      s <- get
      return $ msLogEnv s
  -- (LogEnv -> LogEnv) -> m a -> m a
  localLogEnv f (MyStack m) = MyStack (withStateT (\s -> s { msLogEnv = f (msLogEnv s)}) m)

instance (MonadState MyState (MyStack m), Katip (MyStack m)) => KatipContext (MyStack m) where
  getKatipContext = do
      s <- get
      return $ msKContext s
  localKatipContext f (MyStack m) = MyStack (withStateT (\s -> s { msKContext = f (msKContext s)}) m)
  -- local (\s -> s { msKContext = f (msKContext s)}) m)
  getKatipNamespace = get >>= \x -> return $ msKNamespace x
  localKatipNamespace f (MyStack m) = MyStack (withStateT (\s -> s { msKNamespace = f (msKNamespace s)}) m)


cacheCheckValidity :: CacheId -> MyStack IO Bool
cacheCheckValidity cid = return False



data CLIArguments = CLIArguments {
  _input :: Maybe FilePath
  , version    :: Bool  -- ^ to show version
  , cacheDir    :: Maybe FilePath -- ^ Folder where to log files
  , logLevel :: Severity   -- ^ what level to use to parse
  }


loggerName :: String
loggerName = "main"


data Sample = Sample
  { hello      :: String
  , quiet      :: Bool
  , enthusiasm :: Int }


-- noCompletion
-- type CompletionFunc (m :: Type -> Type) = (String, String) -> m (String, [Completion])
-- https://hackage.haskell.org/package/optparse-applicative-0.15.1.0/docs/Options-Applicative.html#t:Parser
-- optparse :: MonadIO m => Parser a -> CompletionFunc m
-- completeFilename
-- listFiles
-- autocompletion for optparse
-- https://github.com/sdiehl/repline/issues/32
-- data Parser a
--   = NilP (Maybe a)
--   | OptP (Option a)
--   | forall x . MultP (Parser (x -> a)) (Parser x)
--   | AltP (Parser a) (Parser a)
--   | forall x . BindP (Parser x) (x -> Parser a)
-- generateCompleter :: MonadIO m => Parser a -> CompletionFunc m
-- generateCompleter (NilP _) = noCompletion
-- -- mapParser looks cool
-- -- OpT should have optProps and optMain
-- -- en fait c'est le optReader qui va decider de tout
-- -- todo we should react depending on ParseError
-- -- CompletionResult
-- generateCompleter (OptP opt) = noCompletion

sample :: Parser CLIArguments
sample = CLIArguments
      <$> (optional $ strOption
          ( long "load"
          <> short 'l'
         <> help "Either a pcap or a csv file (in good format).\
                 \When a pcap is passed, mptcpanalyzer will look for a its cached csv.\
                 \If it can't find one (or with the flag --regen), it will generate a \
                 \csv from the pcap with the external tshark program."
         <> metavar "INPUT_FILE" ))
      <*> switch (
          long "version"
          <> help "Show version"
          )
      <*> (optional $ strOption
          ( long "cachedir"
         <> help "mptcpanalyzer creates a cache of files in the folder \
            \$XDG_CACHE_HOME/mptcpanalyzer"
         -- <> showDefault
         -- <> Options.Applicative.value "/tmp"
         <> metavar "CACHEDIR" ))
      <*> option auto
          ( long "log-level"
         <> help "Log level"
         <> showDefault
         <> Options.Applicative.value InfoS
         <> metavar "LOG_LEVEL" )


opts :: ParserInfo CLIArguments
opts = info (sample <**> helper)
  ( fullDesc
  <> progDesc "Tool to provide insight in MPTCP (Multipath Transmission Control Protocol)\
              \performance via the generation of stats & plots"
  <> header "hello - a test for optparse-applicative"
  <> footer "You can report issues/contribute at https://github.com/teto/mptcpanalyzer"
  )

-- https://github.com/sdiehl/repline/issues/32
-- data Parser a
--   = NilP (Maybe a)
--   | OptP (Option a)
--   | forall x . MultP (Parser (x -> a)) (Parser x)
--   | AltP (Parser a) (Parser a)
--   | forall x . BindP (Parser x) (x -> Parser a)

-- TODO change
-- type Repl a = HaskelineT IO a

-- ini :: Repl ()
-- ini = liftIO $ putStrLn "Welcome!"

-- -- Commands
-- mainHelp :: [String] -> Repl ()
-- mainHelp args = liftIO $ print $ "Help: " ++ show args

-- say :: [String] -> Repl ()
-- say args = do
--   _ <- liftIO $ system $ "cowsay" ++ " " ++ (unwords args)
--   return ()

-- options :: [(String, [String] -> Repl ())]
-- options = [
--     ("help", mainHelp)  -- :help
--   , ("say", say)    -- :say
--   , ("load", cmdLoadPcap)    -- :say
--   ]
-- repl :: IO ()
-- repl = evalRepl (pure ">>> ") cmd options Nothing (Word completer) ini
-- Evaluation : handle each line user inputs

-- cmd :: String -> Repl ()
-- cmd input = liftIO $ print input

-- -- Tab Completion: return a completion for partial words entered
-- completer :: Monad m => WordCompleter m
-- completer n = do
--   let names = ["load", "listConnections", "listMptcpConnections"]
--   return $ filter (isPrefixOf n) names

-- data CompleterStyle m , I can use a Custom one
-- mainRepline :: IO ()
-- mainRepline = evalRepl (pure ">>> ") cmd Main.options Nothing (Word Main.completer) ini



-- cmdLoadPcap :: [String] -> Repl ()
-- cmdLoadPcap args = do
--   return ()

loadCsv :: (Cache m, MonadIO m, KatipContext m) => FilePath -> m PcapFrame
loadCsv csvFile = do
    frame <- liftIO $ loadRows csvFile
    return frame


-- just for testing, to remove afterwards
defaultPcap :: FilePath
defaultPcap = "examples/client_2_filtered.pcapng"

-- instance MonadException m => MonadException (StateT s m) where
--     controlIO f = StateT $ \s -> controlIO $ \(RunIO run) -> let
--                     run' = RunIO (fmap (StateT . const) . run . flip runStateT s)
--                     in fmap (flip runStateT s) $ f run'


main :: IO ()
main = do

  cacheFolder <- getXdgDirectory XdgCache "mptcpanalyzer"
  -- Create cache if doesn't exist
  doesDirectoryExist cacheFolder >>= \x -> case x of
      True -> putStrLn ("cache folder already exists" ++ show cacheFolder)
      False -> createDirectory cacheFolder

  handleScribe <- mkHandleScribe ColorIfTerminal stdout (permitItem DebugS) V1
  katipEnv <- initLogEnv "mptcpanalyzer" "devel"
  mkLogEnv <- registerScribe "stdout" handleScribe defaultScribeSettings katipEnv
  let myState = MyState {
    _cacheFolder = cacheFolder,
    msKNamespace = "devel",
    msLogEnv = mkLogEnv,
    msKContext = mempty,
    loadedFile = Nothing,
    prompt = "> "
  }

  -- putStrLn $ "Result " ++ show res
  -- TODO preload the pcap file if passed on
  options <- execParser opts

  flip runStateT myState $ do
      unAppT (runInputT defaultSettings inputLoop)


  -- mFrame <- flip evalStateT myState $ do
  --   unAppT (loadPcap defaultTsharkPrefs defaultPcap)

  -- case mFrame of
  --   --  ++ show frame
  --   Just frame ->  do
  --       putStrLn $ "show frame"
  --       listTcpConnections frame
  --   Nothing -> putStrLn "frame not loaded"

  putStrLn "Thanks for flying with mptcpanalyzer"

-- type MptcpAnalyzer m = (Cache m, MonadIO m, KatipContext m, MonadException m, MonadState MyState m)



-- type CommandCb = (CMD.CommandConstraint m) => [String] -> m ()
type CommandCb m = [String] -> m ()

commands :: HM.HashMap String (CommandCb (MyStack IO))
commands = HM.fromList [
    ("load", loadPcap),
    ("list_tcp", listTcpConnections)
    -- ("list_mptcp", listMpTcpConnections)
    ]

-- | Main loop of the program, will run commands in turn
-- TODO pass a dict of command ? that will parse
inputLoop :: InputT (MyStack IO) ()
inputLoop = do
    s <- lift $ get

    minput <- getInputLine (prompt s)
    cmdCode <- case minput of
        Nothing -> do
          liftIO $ putStrLn "please enter a valid command"
          return CMD.Continue
        Just fullCmd -> do
          let commandStr = head $ words fullCmd
          HM.lookup commandStr commands >>= \case
              Nothing -> putStrLn "Unknown command" >> return CMD.Continue
          -- fmap commandCb strings
          return CMD.Continue

    case cmdCode of
        CMD.Exit -> return ()
        _behavior -> inputLoop


-- type TcpStreamT = "tcpstream" :-> Word32


data SimpleData = SimpleData {
      mainStr :: String
      , optionalHello      :: String
    }

-- simpleParser :: Parser SimpleData
-- simpleParser = SimpleData
--       -- action "filepath"
--       <$> argument str (metavar "NAME" <> completeWith ["toto", "tata"])
--       <*> strOption
--           ( long "hello"
--          <> metavar "TARGET"
--          <> help "Target for the greeting" )

