module Main where

import System.IO
import System.Posix.Env
import System.Posix.Files
import System.Posix.Directory
import qualified System.Environment as E
import System.Console.GetOpt

import Control.Monad
import Control.Applicative
import Control.Monad.Trans
import Control.Monad.Trans.Resource
import Control.Exception

import Data.Maybe
import Data.Char
import Data.Word
import qualified Data.ByteString as BS

import Haskoin.Wallet
import Haskoin.Wallet.Store
import Haskoin.Script
import Haskoin.Protocol
import Haskoin.Crypto
import Haskoin.Util

data Options = Options
    { optCount    :: Int
    , optRequire  :: Int
    , optSigHash  :: SigHash
    , optHelp     :: Bool
    , optVersion  :: Bool
    } deriving (Eq, Show)

defaultOptions = Options
    { optCount    = 5
    , optRequire  = 2
    , optSigHash  = SigAll False
    , optHelp     = False
    , optVersion  = False
    } 

options :: [OptDescr (Options -> IO Options)]
options =
    [ Option ['c'] ["count"] (ReqArg parseCount "INT") $
        "Address count. Implies list or genaddr command."
    , Option ['r'] ["require"] (ReqArg parseRequire "INT") $
        "Number of required keys (M) when generating M of N addresses"
    , Option ['H'] ["sighash"] (ReqArg parseSigHash "SIGHASH") $
        "Type of signature. Can be ALL|NONE|SINGLE"
    , Option ['A'] ["anyonecanpay"]
        (NoArg $ \opts -> do
            let sh = optSigHash opts
            return opts{ optSigHash = sh{ anyoneCanPay = True } }
        ) $ "Sign a transaction with the AnyoneCanPay flag set"
    , Option ['h'] ["help"]
        (NoArg $ \opts -> return opts{ optHelp = True }) $
        "Display this help message"
    , Option ['v'] ["version"]
        (NoArg $ \opts -> return opts{ optVersion = True }) $
        "Display wallet version information"
    ]

parseCount :: String -> Options -> IO Options
parseCount s opts 
    | res > 0   = return opts{ optCount = res }
    | otherwise = error $ "Invalid count option: " ++ s
    where res = read s

parseRequire :: String -> Options -> IO Options
parseRequire s opts 
    | res >= 1 && res <= 16 = return opts{ optRequire = res }
    | otherwise = error $ "Invalid require option (between 1 and 16): " ++ s
    where res = read s

parseSigHash :: String -> Options -> IO Options
parseSigHash s opts = return opts{ optSigHash = res }
    where acp = anyoneCanPay $ optSigHash opts
          res | s == "ALL" = SigAll acp
              | s == "NONE" = SigNone acp
              | s == "SINGLE" = SigSingle acp
              | otherwise = error "Invalid SigHash. Has to be ALL|NONE|SINGLE"

usageHeader :: String
usageHeader = "Usage: hw [<options>] <command> [<args>]"

cmdHelp :: String
cmdHelp = 
    "Valid hw commands: \n" 
 ++ "  init         <seed>                               " 
 ++ "Initialize a new wallet from a seed\n"
 ++ "  list         [acc]                                "
 ++ "Display a list of your most recently generated addresses\n" 
 ++ "  listfrom     <from> [acc]                         "
 ++ "Display addresses from an index\n" 
 ++ "  listall      [acc]                                "
 ++ "Display all addresses\n" 
 ++ "  new          <label> [acc]                        "
 ++ "Generate one new address with a label\n"
 ++ "  genaddr      [acc]                                "
 ++ "Generate new addresses\n"
 ++ "  label        <index> <label> [acc]                "
 ++ "Add a label to an address\n"
 ++ "  focus        <acc>                                "
 ++ "All commands will default to the focused account\n"
 ++ "  newacc       <name>                               "
 ++ "Create a new account\n"
 ++ "  listacc                                           "
 ++ "List all the accounts in this wallet\n"
 ++ "  dumpkey      [acc]                                "
 ++ "Dump the specified account public key to stdout\n"
 ++ "  decodetx     <tx>                                 "
 ++ "Decode a transaction provided in HEX format\n"
 ++ "  buildtx      '[(\"txid\",idx)]' '[(\"addr\",amnt)]'   "
 ++ "Build a new transaction from a list of outpoints and destinations\n"

warningMsg :: String
warningMsg = "\n**This software is experimental. " 
    ++ "Use only small amounts of Bitcoins**\n"

versionMsg :: String
versionMsg = "haskoin wallet version 0.1.1.0"

usage :: String
usage = usageInfo usageHeader options ++ cmdHelp

main :: IO ()
main = do
    putStrLn warningMsg
    args <- E.getArgs
    case getOpt Permute options args of
        (o,n,[]) -> do
            opts <- foldl (>>=) (return defaultOptions) o
            process opts n
        (_,_,msgs) ->
            putStrLn $ concat msgs ++ usageInfo usageHeader options

-- Get Haskoin home directory
getHome :: IO FilePath
getHome = do
    haskoinHome <- getEnv "HASKOIN_HOME" 
    if isJust haskoinHome 
        then return $ fromJust haskoinHome
        else do
            home <- getEnv "HOME"
            unless (isJust home) $ error $
                "Please set $HASKOIN_HOME or $HOME environment variables" 
            return $ fromJust home

-- Create and return haskoin working directory
getWorkDir :: IO FilePath
getWorkDir = do
    home <- getHome
    let haskoinDir = home ++ "/.haskoin"
        walletDir  = haskoinDir ++ "/wallet"
    e1 <- fileExist haskoinDir
    unless e1 $ createDirectory haskoinDir ownerModes
    e2 <- fileExist walletDir
    unless e2 $ do
        createDirectory walletDir ownerModes
        putStrLn $ "Haskoin working directory created: " ++ walletDir
    return walletDir

process :: Options -> [String] -> IO ()
process opts cs 
    -- -h and -v can be called without a command
    | optHelp opts = putStrLn usage
    | optVersion opts = putStrLn versionMsg
    -- otherwise require a command
    | null cs = putStrLn usage
    | otherwise = getWorkDir >>= \dir -> do
        let (c,args) = (head cs, tail cs)
        runResourceT $ runWalletDB dir $ checkInit c >> case c of
            "init"      -> cmdInit opts args
            "list"      -> cmdList opts args
            "listfrom"  -> cmdListFrom opts args
            "listall"   -> cmdListAll opts args
            "new"       -> cmdNew opts args
            "genaddr"   -> cmdGenAddr opts args
            "label"     -> cmdLabel args
            "focus"     -> cmdFocus opts args
            "newacc"    -> cmdNewAcc opts args
            "listacc"   -> cmdListAcc 
            "dumpkey"   -> cmdDumpKey args
            "decodetx"  -> cmdDecodeTx opts args
            "buildtx"   -> cmdBuildTx opts args
            "signtx"    -> liftIO $ putStrLn "Command not implemented"
            _           -> error $ "Invalid command: " ++ c
        putStrLn ""

type Args = [String]
type CmdAction = WalletDB (ResourceT IO) ()

checkInit :: String -> CmdAction
checkInit "init" = return ()
checkInit _ = isDBInit >>= \init -> unless init $ error $
    "Database is not initialized. You must call 'init' first."

-- Return the account from the arguments, or get the current focused account
getArgsAcc :: Args -> WalletDB (ResourceT IO) String
getArgsAcc args = case args of
    [] -> fromJust <$> dbGetFocus
    acc:[] -> return acc

formatAddr :: WAddr -> IO ()
formatAddr (WAddr a l _ p _ _)
    | null l    = putStrLn def
    | otherwise = putStrLn $ def ++ lab
    where def = (show $ p) ++ ") " ++ a
          lab = " (" ++ l ++ ")"

formatPages :: Int -> Int -> WAccount -> IO ()
formatPages from count acc = do
    putStr $ "Account: " ++ accName acc
    putStr $ " (Addresses " ++(show from) ++ " to " ++ (show $ from + count - 1) 
    putStrLn $ " of " ++ (show $ accExtCount acc) ++ ")"

cmdInit :: Options -> Args -> CmdAction
cmdInit opts args
    | length args /= 1 = liftIO $ putStr usage
    | otherwise = do
        dbInit $ head args
        cmdGenAddr opts [] -- generate some addresses

cmdList :: Options -> Args -> CmdAction
cmdList opts args 
    | length args > 1 = liftIO $ putStr usage
    | otherwise = do
        name <- getArgsAcc args
        acc  <- fromJust <$> dbGetAcc name
        let total = accExtCount acc
            count = min (optCount opts) total
        addr <- dbListExtAddr name (total - count + 1) count
        liftIO $ formatPages (total - count + 1) (length addr) acc
        liftIO $ forM_ addr formatAddr

cmdListFrom :: Options -> Args -> CmdAction
cmdListFrom opts args 
    | length args > 2 = liftIO $ putStr usage
    | otherwise = do
        name <- getArgsAcc $ drop 1 args
        acc  <- fromJust <$> dbGetAcc name
        addr <- dbListExtAddr name from $ optCount opts
        liftIO $ if null addr
            then putStrLn "No addresses to display"
            else do
                formatPages from (length addr) acc
                forM_ addr formatAddr
    where from = read $ args !! 0

cmdListAll :: Options -> Args -> CmdAction
cmdListAll opts args 
    | length args > 1 = liftIO $ putStr usage
    | otherwise = do
        name <- getArgsAcc args
        acc <- fromJust <$> dbGetAcc name
        addr <- dbListExtAddr name 1 (accExtCount acc)
        liftIO $ formatPages 1 (length addr) acc
        liftIO $ forM_ addr formatAddr

cmdNew :: Options -> Args -> CmdAction
cmdNew opts args 
    | length args > 2 = liftIO $ putStr usage
    | otherwise = do
        name <- getArgsAcc $ drop 1 args
        waddr <- head <$> (dbGenExtAddr name 1)
        let newAddr = waddr{ wLabel = args !! 0 }
        dbPutAddr newAddr
        liftIO $ putStrLn $ "Account: " ++ name
        liftIO $ formatAddr newAddr

cmdGenAddr :: Options -> Args -> CmdAction
cmdGenAddr opts args 
    | length args > 1 = liftIO $ putStr usage
    | otherwise = do
        name <- getArgsAcc args
        addr <- dbGenExtAddr name $ optCount opts
        cmdList opts args

cmdFocus :: Options -> Args -> CmdAction
cmdFocus opts args
    | length args /= 1 = liftIO $ putStr usage
    | otherwise = do
        dbPutFocus $ head args 
        cmdList opts args

cmdNewAcc :: Options -> Args -> CmdAction
cmdNewAcc opts args
    | length args /= 1 = liftIO $ putStr usage
    | otherwise = do
        dbNewAcc $ head args 
        cmdGenAddr opts args

cmdListAcc :: CmdAction
cmdListAcc = dbListAcc >>= \accs -> liftIO $ do
    putStrLn "R = Regular account, M = Multisig account\n"
    forM_ accs $ \acc -> liftIO $ do
        putStr $ if isMSAcc acc then "[M] " else "[R] "
        putStr $ accName acc 
        putStrLn $ " (" ++ (show $ accExtCount acc) ++ " addresses)"

cmdLabel :: Args -> CmdAction
cmdLabel args
    | length args > 3 = liftIO $ putStr usage
    | otherwise = do
        name <- getArgsAcc $ drop 2 args
        acc  <- fromJust <$> (dbGetAcc name)
        prev <- dbGetAddrByPos name p
        case prev of
            Nothing    -> error $ "Address index not in wallet: " ++ (show p)
            Just waddr -> do
                let newAddr = waddr{ wLabel = args !! 1 }
                dbPutAddr newAddr
                liftIO $ putStrLn $ "Account: " ++ accName acc
                liftIO $ formatAddr newAddr
    where p = read (args !! 0) 

cmdDumpKey :: Args -> CmdAction
cmdDumpKey args 
    | length args > 1 = liftIO $ putStr usage
    | otherwise = do
        name <- getArgsAcc args
        acc  <- fromJust <$> dbGetAcc name
        liftIO $ putStrLn $ "Account: " ++ accName acc
        liftIO $ putStrLn $ xPubExport $ runAccPubKey $ accKey acc

cmdDecodeTx :: Options -> Args -> CmdAction
cmdDecodeTx opts args
    | null args = liftIO $ putStrLn usage
    | isNothing bs = error "<tx>: Invalid HEX encoding"
    | otherwise = case eitherTx of
        Left err -> error err
        Right tx -> liftIO $ pp tx
    where bs       = hexToBS $ head args
          eitherTx = decodeToEither $ fromJust bs :: Either String Tx

cmdBuildTx :: Options -> Args -> CmdAction
cmdBuildTx opts args
    | length args /= 2 = liftIO $ putStr usage
    | otherwise = case buildAddrTx (map f os) as of
        Right tx -> liftIO $ putStrLn $ bsToHex $ encode' tx
        Left err -> error err
    where os = read (args !! 0) :: [(String,Word32)]
          as = read (args !! 1) :: [(String,Word64)]
          f (s,i) = OutPoint (decode' $ BS.reverse $ fromJust $ hexToBS s) i

--cmdSignTx :: Options -> Args -> CmdAction
--cmdSignTx m opts args
--    | length args < 3 || length args > 4 = error usage
--    | isNothing bs = error "<tx>: Invalid HEX encoding"
--    | otherwise = case eitherTx of
--        Left err -> error err
--        Right tx -> lift $ putStrLn $ show $
--            liftM (bsToHex . encode') (detSignTx tx (map (g . f) os) $ map h is)
--    where ai  = fromIntegral $ optAccount opts
--          acc = fromMaybe (error $ "Invalid account index") $ accPrvKey m ai
--          bs = hexToBS $ args !! 0
--          eitherTx = decodeToEither $ fromJust bs :: Either String Tx
--          os = read (args !! 1) :: [(String,Word32,String)]
--          is = read (args !! 2) :: [Word32]
--          keys = map (fromJust . xPubImport) $ drop 3 args
--          f (t,i,s) = ( (Script $ runGet' getScriptOps $ fromJust $ hexToBS s) 
--                      , ( OutPoint 
--                            (decode' $ BS.reverse $ fromJust $ hexToBS t) 
--                            i
--                        )
--                      )
--          g (s,o) | null keys = SigInput s o $ optSigHash opts
--                  | otherwise = SigInputSH s o rdm $ optSigHash opts
--                  where rdm = encodeOutput $
--                              PayMulSig (map xPubKey keys) (optRequire opts)
--          h i = xPrvKey $ runAddrPrvKey $ fromJust $ 
--                    if (optInternal opts) then intPrvKey acc i
--                                          else extPrvKey acc i
        

