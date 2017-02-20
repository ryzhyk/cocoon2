{-# LANGUAGE FlexibleContexts #-}

module Parse ( cocoonGrammar
             , cfgGrammar) where

import Control.Applicative hiding (many,optional,Const)
import Control.Monad
import Text.Parsec hiding ((<|>))
import Text.Parsec.Expr
import Text.Parsec.Language
import qualified Text.Parsec.Token as T
import Data.Maybe
import Data.Either
import Numeric

import Syntax
import Pos
import Util

reservedOpNames = [":", "?", "!", "|", "==", "=", ":-", "%", "+", "-", ".", "->", "=>", "<=", "<=>", ">=", "<", ">", "!=", ">>", "<<"]
reservedNames = ["_",
                 "and",
                 "any",
                 "assume",
                 "bit",
                 "bool",
                 "check",
                 "default",
                 "drop",
                 "else",
                 "false",
                 "foreign",
                 "fork",
                 "function",
                 "host",
                 "if",
                 "in",
                 "int",
                 "key",
                 "match",
                 "sink",
                 "not",
                 "or",
                 "pkt",
                 "primary",
                 "procedure",
                 "references",
                 "refine",
                 "role",
                 "send",
                 "state",
                 "string",
                 "switch",
                 "table",
                 "true",
                 "typedef",
                 "unique",
                 "var",
                 "view",
                 "with"]


ccnDef = emptyDef { T.commentStart      = "/*"
                  , T.commentEnd        = "*/"
                  , T.commentLine       = "//"
                  , T.nestedComments    = True
                  , T.identStart        = letter <|> char '_' 
                  , T.identLetter       = alphaNum <|> char '_'
                  , T.reservedOpNames   = reservedOpNames
                  , T.reservedNames     = reservedNames
                  , T.opLetter          = oneOf "!?:%*-+./=|<>"
                  , T.caseSensitive     = True}

ccnLCDef = ccnDef{T.identStart = lower <|> char '_'}
ccnUCDef = ccnDef{T.identStart = upper}

lexer   = T.makeTokenParser ccnDef
lcLexer = T.makeTokenParser ccnLCDef
ucLexer = T.makeTokenParser ccnUCDef

reservedOp   = T.reservedOp lexer
reserved     = T.reserved lexer
identifier   = T.identifier lexer
lcIdentifier = T.identifier lcLexer
ucIdentifier = T.identifier ucLexer
--semiSep    = T.semiSep lexer
--semiSep1   = T.semiSep1 lexer
colon        = T.colon lexer
commaSep     = T.commaSep lexer
commaSep1    = T.commaSep1 lexer
symbol       = T.symbol lexer
semi         = T.semi lexer
comma        = T.comma lexer
braces       = T.braces lexer
parens       = T.parens lexer
angles       = T.angles lexer
brackets     = T.brackets lexer
natural      = T.natural lexer
decimal      = T.decimal lexer
--integer    = T.integer lexer
whiteSpace   = T.whiteSpace lexer
lexeme       = T.lexeme lexer
dot          = T.dot lexer
stringLit    = T.stringLiteral lexer
--charLit    = T.charLiteral lexer

roleIdent = ucIdentifier
consIdent = ucIdentifier
varIdent  = lcIdentifier
funcIdent = lcIdentifier

removeTabs = do s <- getInput
                let s' = map (\c -> if c == '\t' then ' ' else c ) s 
                setInput s'          

withPos x = (\s a e -> atPos a (s,e)) <$> getPosition <*> x <*> getPosition


data SpecItem = SpType         TypeDef
              | SpState        Field
              | SpRelation     Relation
              | SpAssume       Assume
              | SpFunc         Function
              | SpRole         Role
              | SpNode         Node


cocoonGrammar = Spec <$ removeTabs <*> ((optional whiteSpace) *> spec <* eof)
cfgGrammar = removeTabs *> ((optional whiteSpace) *> (many relation) <* eof)

spec = (\r rs -> r:rs) <$> (withPos $ mkRefine [] <$> (many decl)) <*> (many refine)

mkRefine :: [String] -> [SpecItem] -> Refine
mkRefine targets items = Refine nopos targets types state funcs relations assumes roles nodes
    where types = mapMaybe (\i -> case i of 
                                       SpType t -> Just t
                                       _        -> Nothing) items
          state = mapMaybe (\i -> case i of 
                                       SpState s -> Just s
                                       _         -> Nothing) items
          funcs = mapMaybe (\i -> case i of 
                                       SpFunc f -> Just f
                                       _        -> Nothing) items
          roles = mapMaybe (\i -> case i of 
                                       SpRole r -> Just r
                                       _        -> Nothing) items
          relations = mapMaybe (\i -> case i of 
                                           SpRelation r -> Just r
                                           _            -> Nothing) items
          assumes = mapMaybe (\i -> case i of 
                                       SpAssume a -> Just a
                                       _          -> Nothing) items
          nodes = mapMaybe (\i -> case i of 
                                       SpNode n -> Just n
                                       _        -> Nothing) items

refine = withPos $ mkRefine <$  reserved "refine" 
                            <*> (commaSep roleIdent)
                            <*> (braces $ many decl)

decl =  (SpType         <$> typeDef)
    <|> (SpRelation     <$> relation)
    <|> (SpState        <$> stateVar)
    <|> (SpFunc         <$> func)
    <|> (SpFunc         <$> proc)
    <|> (SpRole         <$> role)
    <|> (SpAssume       <$> assume)
    <|> (SpNode         <$> node)


typeDef = withPos $ (TypeDef nopos) <$ reserved "typedef" <*> identifier <*> (optionMaybe $ reservedOp "=" *> typeSpec)

stateVar = withPos $ reserved "state" *> arg

func = withPos $ Function nopos True <$  reserved "function"
                                     <*> funcIdent
                                     <*> (parens $ commaSep arg) 
                                     <*> (colon *> typeSpecSimple)
                                     <*> (option (eBool True) (reservedOp "|" *> expr))
                                     <*> (optionMaybe $ reservedOp "=" *> expr)

proc = withPos $ Function nopos False <$  reserved "procedure"
                                      <*> funcIdent
                                      <*> (parens $ commaSep arg) 
                                      <*> (colon *> typeSpecSimple)
                                      <*> (option (eBool True) (reservedOp "|" *> expr))
                                      <*> (Just <$ reservedOp "=" <*> expr)

relation = withPos $ do mutable <- (True <$ ((try $ lookAhead $ reserved "state" *> reserved "table") *> (reserved "state" *> reserved "table")))
                                   <|>
                                   (False <$ reserved "table")
                        n <- identifier
                        (as, cs) <- liftM partitionEithers $ parens $ commaSep argOrConstraint
                        return $ Relation nopos mutable n as cs Nothing
                 <|> do reserved "view" 
                        n <- identifier
                        (as, cs) <- liftM partitionEithers $ parens $ commaSep argOrConstraint
                        rs <- many1 $ withPos $ do 
                                      try $ lookAhead $ identifier *> (parens $ commaSep expr) *> reservedOp ":-"
                                      rn <- identifier
                                      when (rn /= n) $ fail $ "Only rules for relation \"" ++ n ++ "\" can be defined here"
                                      rargs <- parens $ commaSep expr
                                      reservedOp ":-"
                                      rhs <- commaSep expr
                                      return $ Rule nopos rargs rhs
                        return $ Relation nopos False n as cs $ Just rs

argOrConstraint =  (Right <$> constraint)
               <|> (Left  <$> arg)

constraint = withPos $  (PrimaryKey nopos <$ reserved "primary" <*> (reserved "key" *> (parens $ commaSep expr)))
                    <|> (ForeignKey nopos <$ reserved "foreign" <*> (reserved "key" *> (parens $ commaSep expr)) 
                                          <*> (reserved "references" *> identifier) <*> (parens $ commaSep expr))
                    <|> (Unique     nopos <$ reserved "unique" <*> (parens $ commaSep expr))
                    <|> (Check      nopos <$ reserved "check" <*> expr)


role = withPos $ (\n (k, t, c, pc) b -> Role nopos n k t c pc b) 
               <$  reserved "role" 
               <*> roleIdent 
               <*> (brackets $ (,,,)
                           <$> varIdent
                           <*> (reserved "in" *> identifier)
                           <*> (option (eBool True) (reservedOp "|" *> expr))
                           <*> (option (eBool True) (reservedOp "/" *> expr)))
               <*> (reservedOp "=" *> expr)

assume = withPos $ Assume nopos <$ reserved "assume" <*> (option [] $ parens $ commaSep arg) <*> expr

node = withPos $ Node nopos <$> ((NodeSwitch <$ reserved "switch") <|> (NodeHost <$ reserved "host"))
                            <*> identifier 
                            <*> (parens $ commaSep1 $ parens $ (,) <$> roleIdent <* comma <*> roleIdent)

arg = withPos $ (Field nopos) <$> varIdent <*> (colon *> typeSpecSimple)

typeSpec = withPos $ 
            arrType
        <|> bitType 
        <|> intType
        <|> stringType
        <|> boolType 
        <|> structType 
        <|> userType 
        <|> tupleType
        
typeSpecSimple = withPos $ 
                  arrType
              <|> bitType 
              <|> intType
              <|> stringType
              <|> boolType 
              <|> tupleType
              <|> userType 

bitType    = TBit    nopos <$ reserved "bit" <*> (fromIntegral <$> angles decimal)
intType    = TInt    nopos <$ reserved "int"
stringType = TString nopos <$ reserved "string"
boolType   = TBool   nopos <$ reserved "bool"
userType   = TUser   nopos <$> identifier
arrType    = brackets $ TArray nopos <$> typeSpecSimple <* semi <*> (fromIntegral <$> decimal)
structType = TStruct nopos <$ isstruct <*> sepBy1 constructor (reservedOp "|") 
    where isstruct = try $ lookAhead $ consIdent *> (symbol "{" <|> symbol "|")
tupleType  = (\fs -> case fs of
                          [f] -> f
                          _   -> TTuple nopos fs)
             <$> (parens $ commaSep typeSpecSimple)

constructor = withPos $ Constructor nopos <$> consIdent <*> (option [] $ braces $ commaSep arg)

expr =  buildExpressionParser etable term
    <?> "expression"

term  =  (withPos $ eTuple <$> (parens $ commaSep expr))
     <|> braces expr
     <|> term'
term' = withPos $
         eapply
     <|> eloc
     <|> estruct
     <|> eint
     <|> ebool
     <|> estring
     <|> epacket
     <|> evar
     <|> ematch
     <|> edrop
     <|> eite
     <|> esend
     <|> evardcl
     <|> efork
     <|> ewith
     <|> eany
     <|> elhs

eapply = eApply <$ isapply <*> funcIdent <*> (parens $ commaSep expr)
    where isapply = try $ lookAhead $ funcIdent *> symbol "("
eloc = eLocation <$ isloc <*> roleIdent <*> (brackets expr)
    where isloc = try $ lookAhead $ roleIdent *> (brackets expr)
ebool = eBool <$> ((True <$ reserved "true") <|> (False <$ reserved "false"))
epacket = ePacket <$ reserved "pkt"
evar = eVar <$> varIdent
ematch = eMatch <$ reserved "match" <*> parens expr
               <*> (braces $ (commaSep1 $ (,) <$> pattern <* reservedOp "->" <*> expr))
pattern = withPos $ 
          eTuple   <$> (parens $ commaSep pattern)
      <|> eVarDecl <$> varIdent
      <|> epholder
      <|> eStruct  <$> consIdent <*> (option [] $ braces $ commaSep pattern)

lhs = withPos $ 
          eTuple <$> (parens $ commaSep lhs)
      <|> evar
      <|> evardcl
      <|> epholder
      <|> eStruct <$> consIdent <*> (option [] $ braces $ commaSep lhs)
elhs = islhs *> lhs
    where islhs = try $ lookAhead $ lhs *> reservedOp "="

--eint  = Int <$> (fromIntegral <$> decimal)
eint  = lexeme eint'
estring = eString <$> stringLit
estruct = eStruct <$> consIdent <*> (option [] $ braces $ commaSep expr)

eint'   = (lookAhead $ char '\'' <|> digit) *> (do w <- width
                                                   v <- sradval
                                                   mkLit w v)

edrop   = eDrop    <$ reserved "drop"
esend   = eSend    <$ reserved "send" <*> expr
eite    = eITE     <$ reserved "if" <*> expr <*> expr <*> (optionMaybe $ reserved "else" *> expr)
evardcl = eVarDecl <$ reserved "var" <*> varIdent
efork   = eFork    <$ reserved "fork" 
                   <*> (symbol "(" *> varIdent)
                   <*> (reserved "in" *> identifier) 
                   <*> ((option (eBool True) (reservedOp "|" *> expr)) <* symbol ")")
                   <*> expr
ewith   = eWith    <$ reserved "with" 
                   <*> (symbol "(" *> varIdent)
                   <*> (reserved "in" *> identifier) 
                   <*> ((option (eBool True) (reservedOp "|" *> expr)) <* symbol ")")
                   <*> expr
                   <*> (optionMaybe $ reserved "default" *> expr)

eany    = eAny <$ reserved "any" 
               <*> (symbol "(" *> varIdent)
               <*> (reserved "in" *> identifier) 
               <*> ((option (eBool True) (reservedOp "|" *> expr)) <* symbol ")")
               <*> expr
               <*> (optionMaybe $ reserved "default" *> expr)
epholder = ePHolder <$ reserved "_"

width = optionMaybe (try $ ((fmap fromIntegral parseDec) <* (lookAhead $ char '\'')))
sradval =  ((try $ string "'b") *> parseBin)
       <|> ((try $ string "'o") *> parseOct)
       <|> ((try $ string "'d") *> parseDec)
       <|> ((try $ string "'h") *> parseHex)
       <|> parseDec
parseBin :: Stream s m Char => ParsecT s u m Integer
parseBin = readBin <$> (many1 $ (char '0') <|> (char '1'))
parseOct :: Stream s m Char => ParsecT s u m Integer
parseOct = (fst . head . readOct) <$> many1 octDigit
parseDec :: Stream s m Char => ParsecT s u m Integer
parseDec = (fst . head . readDec) <$> many1 digit
--parseSDec = (\m v -> m * v)
--            <$> (option 1 ((-1) <$ reservedOp "-"))
--            <*> ((fst . head . readDec) <$> many1 digit)
parseHex :: Stream s m Char => ParsecT s u m Integer
parseHex = (fst . head . readHex) <$> many1 hexDigit

mkLit :: Maybe Int -> Integer -> ParsecT s u m Expr
mkLit Nothing  v                       = return $ eInt v
mkLit (Just w) v | w == 0              = fail "Unsigned literals must have width >0"
                 | msb v < w           = return $ eBit w v
                 | otherwise           = fail "Value exceeds specified width"

etable = [[postf $ choice [postSlice, postApply, postField, postType]]
         ,[pref  $ choice [prefix "not" Not]]
         ,[binary "%" Mod AssocLeft]
         ,[binary "+" Plus AssocLeft,
           binary "-" Minus AssocLeft]
         ,[binary ">>" ShiftR AssocLeft,
           binary "<<" ShiftL AssocLeft]
         ,[binary "++" Concat AssocLeft]
         ,[binary "==" Eq  AssocLeft,          
           binary "!=" Neq AssocLeft,          
           binary "<"  Lt  AssocNone, 
           binary "<=" Lte AssocNone, 
           binary ">"  Gt  AssocNone, 
           binary ">=" Gte AssocNone]
         ,[binary "and" And AssocLeft]
         ,[binary "or" Or AssocLeft]
         ,[binary "=>" Impl AssocLeft]
         ,[assign AssocNone]
         ,[sbinary ";" ESeq AssocRight]
         ,[sbinary "|" EPar AssocRight]
         ]

pref  p = Prefix  . chainl1 p $ return       (.)
postf p = Postfix . chainl1 p $ return (flip (.))
postField = (\f end e -> E $ EField (fst $ pos e, end) e f) <$> field <*> getPosition
postApply = (\(f, args) end e -> E $ EApply (fst $ pos e, end) f (e:args)) <$> dotcall <*> getPosition
postType = (\t end e -> E $ ETyped (fst $ pos e, end) e t) <$> etype <*> getPosition
postSlice  = try $ (\(h,l) end e -> E $ ESlice (fst $ pos e, end) e h l) <$> slice <*> getPosition
slice = brackets $ (\h l -> (fromInteger h, fromInteger l)) <$> natural <*> (colon *> natural)

field = dot *> varIdent
dotcall = (,) <$ isapply <*> (dot *> funcIdent) <*> (parens $ commaSep expr)
    where isapply = try $ lookAhead $ dot *> funcIdent *> symbol "("

etype = reservedOp ":" *> typeSpecSimple

prefix n fun = (\start e -> E $ EUnOp (start, snd $ pos e) fun e) <$> getPosition <* reservedOp n
binary n fun  = Infix $ (\le re -> E $ EBinOp (fst $ pos le, snd $ pos re) fun le re) <$ reservedOp n
sbinary n fun = Infix $ (\l  r  -> E $ fun (fst $ pos l, snd $ pos r) l r) <$ reservedOp n

assign = Infix $ (\l r  -> E $ ESet (fst $ pos l, snd $ pos r) l r) <$ reservedOp "="
