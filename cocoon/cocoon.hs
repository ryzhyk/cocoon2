{-# LANGUAGE RecordWildCards, ImplicitParams #-}

import System.Environment
import Text.Parsec.Prim
import Control.Monad
import System.FilePath.Posix
import Text.PrettyPrint
import Text.Printf
import Data.Maybe
import Data.List
import System.Directory
import System.IO.Error
import System.IO
import Numeric

import Parse
import Validate
import P4.P4
import Topology
import MiniNet.MiniNet
import Name
import Syntax
import NS
import Expr
import PP
import Boogie.Boogie
import Util


main = do
    args <- getArgs
    prog <- getProgName
    when (length args > 3 || length args < 2) $ fail $ "Usage: " ++ prog ++ " <spec_file> <bound> [<config_file>]"
    let fname  = args !! 0
        cfname = if length args >= 3
                    then Just $ args !! 2
                    else Nothing
        (dir, file) = splitFileName fname
        (basename,_) = splitExtension file
        workdir = dir </> basename
    bound <- case readDec (args !! 1) of
                  [(b, _)] -> return b
                  _        -> fail $ "Invalid bound: " ++ (args !! 1)
    createDirectoryIfMissing False workdir
    fdata <- readFile fname
    spec <- case parse cocoonGrammar fname fdata of
                 Left  e    -> fail $ "Failed to parse input file: " ++ show e
                 Right spec -> return spec
    combined <- case validate spec of
                     Left e   -> fail $ "Validation error: " ++ e
                     Right rs -> return rs
    let final = last combined
    putStrLn "Validation complete"

    let ps = pairs combined
    let boogieSpecs = (head combined, refinementToBoogie Nothing (head combined) bound) :
                      map (\(r1,r2) -> (r2, refinementToBoogie (Just r1) r2 bound)) ps
        boogiedir = workdir </> "boogie"
    createDirectoryIfMissing False boogiedir
    oldfiles <- listDirectory boogiedir
    mapM_ (removeFile . (boogiedir </>)) oldfiles
    mapIdxM_ (\(_, (asms, mroles)) i -> do -- putStrLn $ "Verifying refinement " ++ show i ++ " with " ++ (show $ length asms) ++ " verifiable assumptions , " ++ (maybe "_" (show . length) mroles) ++ " roles" 
                                           let specN = printf "spec%02d" i
                                           mapIdxM_ (\(_, b) j -> do writeFile (boogiedir </> addExtension (specN ++ "_asm" ++ show j) "bpl") (render b)) asms
                                           maybe (return ())
                                                 (mapM_ (\(rl, b) -> do writeFile (boogiedir </> addExtension (specN ++ "_" ++ rl) "bpl") (render b)))
                                                 mroles)
             boogieSpecs
    
    putStrLn "Verification condition generation complete"

    topology <- case generateTopology final of
                     Left e  -> fail $ "Error generating network topology: " ++ e
                     Right t -> return t
    let (mntopology, instmap) = generateMininetTopology final topology
        p4switches = genP4Switches final topology
    writeFile (workdir </> addExtension basename "mn") mntopology
    mapM_ (\(P4Switch descr p4 cmd _) -> do let swname = fromJust $ lookup descr instmap
                                            writeFile (workdir </> addExtension (addExtension basename swname) "p4")  (render p4)
                                            writeFile (workdir </> addExtension (addExtension basename swname) "txt") (render cmd)) 
          p4switches      
    -- DO NOT MODIFY this string: the run_network.py script uses it to detect the 
    -- end of the compilation phase
    putStrLn "Network generation complete"
    hFlush stdout

    maybe (return()) (refreshTables workdir basename instmap final Nothing p4switches) cfname

pairs :: [a] -> [(a,a)]
pairs (x:y:xs) = (x,y) : pairs (y:xs)
pairs _        = []

-- Update command files for dynamic actions modified in the new configuration.
-- workdir  - work directory where all P4 files are stored
-- basename - name of the spec to prepended to all filenames
-- base     - base specification before configuration was applied to it
-- prev     - specification with previous configuration
-- switches - switch definitions derived from base
-- cfname   - configuration file
refreshTables :: String -> String -> NodeMap -> Refine -> Maybe Refine -> [P4Switch] -> String -> IO ()
refreshTables workdir basename instmap base prev switches cfname = do
    mcombined <- 
        do cfgdata <- readFile cfname
           cfg <- case parse cfgGrammar cfname cfgdata of
                       Left  e    -> fail $ "Failed to parse config file: " ++ show e
                       Right spec -> return spec
           combined <- case validateConfig base cfg of
                            Left e   -> fail $ "Validation error: " ++ e
                            Right rs -> return rs
           let modFuncs = case prev of 
                               Nothing  -> refineFuncs combined
                               Just old -> filter (\f -> maybe True (f /= ) $ lookupFunc old (name f)) $ refineFuncs combined
               modFNames = map name modFuncs
           putStrLn $ "Functions changed: " ++ (intercalate " " $ map name modFuncs)
           let modSwitches = case prev of
                                  Nothing  -> switches
                                  Just old -> filter (any (not . null . intersect modFNames . map name . exprFuncsRec old . p4dynExpr) . p4DynActs) switches
           mapM_ (\P4Switch{..} -> do let swname = fromJust $ lookup p4Descr instmap
                                          cmds = vcat $ punctuate (pp "") $ p4Init : map (vcat . populateTable combined) p4DynActs
                                      --putStrLn $ "Switch " ++ show p4Descr ++ " " ++ swname  
                                      writeFile (workdir </> addExtension (addExtension basename swname) "txt") (render cmds))
                 modSwitches
           putStrLn $ "Switches updated: " ++ (intercalate " " $ map (\sw -> fromJust $ lookup (p4Descr sw) instmap) modSwitches)

           -- DO NOT MODIFY this string: the run_network.py script uses it to detect the 
           -- end of the compilation phase
           putStrLn "Network configuration complete"
           hFlush stdout
           return $ Just combined
        `catchIOError` 
           \e -> do putStrLn ("Exception: " ++ show e)
                    putStrLn ("Regenerating the entire configuration next time")
                    hFlush stdout
                    return Nothing
    let wait = do inp <- getLine
                  when (inp /= "update") wait
    wait
    refreshTables workdir basename instmap base mcombined switches cfname
