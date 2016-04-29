module Parser where

import AST
import Prelude hiding (Enum)
import Text.ParserCombinators.Parsec
import Text.Parsec.Language (emptyDef)
import Text.Parsec (modifyState, SourcePos, getPosition, getState, putState, sourceLine)
import Control.Monad (void)
import qualified Text.Parsec.Token as Tok

data ParserState = ParserState {
  _comments :: [String]
}

data Tagging = Tagging {
  _comment :: [String],
  _sourcePos :: SourcePos
}

instance Show Tagging where
    show (Tagging comments pos) =
      let line = if length comments > 0 then take 5 (head comments) ++ "..., " else ""
      in  "(" ++ line ++ show (sourceLine pos) ++ ")"

initState :: ParserState
initState = ParserState []

type MyParser = CharParser ParserState

testParse :: MyParser a -> String -> Either ParseError a
testParse p = runParser p initState "webidl"

parseIDL :: String -> Either ParseError [Definition Tagging]
parseIDL = testParse (pSpaces *> many1 (pDef <* pSpaces))

pDef :: MyParser (Definition Tagging)
pDef = DefInterface <$> (pExtAttrs *> pInterface)
   <|> DefPartial <$> pPartial
   <|> DefDictionary <$> pDictionary
   <|> DefException <$> pException
   <|> DefEnum <$> pEnum
   <|> DefTypedef <$> pTypedef
   <|> DefImplementsStatement <$> pImplementsStatement

-- FIXME: currently we ignore extended attributes
pExtAttrs :: MyParser ()
pExtAttrs = pSpaces *> void (char '[' *> (manyTill anyChar (try (char ']')))) <* pSpaces
        <|> pSpaces

pPartial :: MyParser (Partial Tagging)
pPartial = string "partial" *> pSpaces *> p
  where
    p =   PartialInterface <$> getTag <*> (string "interface" *> pSpaces *> pIdent)
                              <*> braces (many pInterfaceMember) <* semi
      <|> PartialDictionary <$> getTag <*> (string "dictionary" *> pSpaces *> pIdent)
                               <*> braces (many pDictionaryMember) <* semi

pDictionary :: MyParser (Dictionary Tagging)
pDictionary = Dictionary <$> getTag <*> (string "dictionary" *> pSpaces *> pIdent)
                         <*> pInheritance <*> braces (many pDictionaryMember) <* semi

pInterface :: MyParser (Interface Tagging)
pInterface = Interface <$> getTag <*> (string "interface" *> pSpaces *> pIdent)
                          <*> pInheritance <*> braces (pSpaces *> many (pInterfaceMember <* pSpaces)) <* semi

pException :: MyParser (Exception Tagging)
pException = Exception <$> getTag <*> (string "exception" *> pSpaces *> pIdent)
                          <*> pInheritance <*> braces (many pExceptionMember)

pInheritance :: MyParser (Maybe Ident)
pInheritance = optionMaybe (spaces *> char ':'  *> spaces *> pIdent)

pEnum :: MyParser (Enum Tagging)
pEnum = Enum <$> getTag <*> (string "enum" *> pSpaces *> pIdent) <*> braces pEnumValues <* semi

pEnumValues :: MyParser [EnumValue]
pEnumValues = sepBy1 (EnumValue <$> stringLit) (char ',')


pTypedef :: MyParser (Typedef Tagging)
pTypedef = do
  tag <- getTag
  string "typedef"
  pSpaces
  ty <- try pType
  pSpaces
  ident <- pIdent
  semi
  return (Typedef tag ty ident)

pImplementsStatement :: MyParser (ImplementsStatement Tagging)
pImplementsStatement = ImplementsStatement <$> getTag <*> pIdent <* pSpaces
                                              <*> (string "implements" *> pSpaces *> pIdent <* semi)

pDictionaryMember :: MyParser (DictionaryMember Tagging)
pDictionaryMember = DictionaryMember <$> getTag <*> pType <* pSpaces
                                     <*> pIdent <*> optionMaybe (spaces *> pEq *> spaces *> pDefault) <* semi

pExceptionMember :: MyParser (ExceptionMember Tagging)
pExceptionMember =  ExConst <$> getTag <*> pConst
                <|> ExField <$> getTag <*> pType <*> pIdent <* semi

pMaybeIdent :: MyParser (Maybe Ident)
pMaybeIdent = optionMaybe pIdent

pInterfaceMember :: MyParser (InterfaceMember Tagging)
pInterfaceMember =  try (IMemConst <$> pConst)
                <|> try (IMemAttribute <$> pAttribute)
                <|> IMemOperation <$> (pExtAttrs *> pOperation)

pConst :: MyParser (Const Tagging)
pConst = Const <$> getTag <*> (string "const" *> pSpaces *> pConstType <* pSpaces)
               <*> (pIdent <* pEq) <*> (pSpaces *> pConstValue <* semi)

pConstType :: MyParser ConstType
pConstType =  ConstPrim <$> pPrimTy <*> pNull
          <|> ConstIdent <$> pIdent <*> pNull

pAttribute :: MyParser (Attribute Tagging)
pAttribute = Attribute <$> getTag <*> pModifier Inherit "inherit"
                       <*> pModifier ReadOnly "readonly"
                       <*> (string "attribute" *> pSpaces *> pType) <*> (pSpaces *> pIdent <* semi)

pModifier :: a -> String -> MyParser (Maybe a)
pModifier m s = optionMaybe (string s *> pSpaces *> return m)

pOperation :: MyParser (Operation Tagging)
pOperation = Operation <$> getTag <*> pQualifier <* spaces
                       <*> pReturnType <* pSpaces
                       <*> pMaybeIdent <* pSpaces
                       <*> parens (pSpaces *> sepBy (pArg <* pSpaces) (char ',' <* pSpaces)) <* semi

pArg :: MyParser Argument
pArg =  ArgOptional <$> (string "optional" *> pType <* pSpaces) <*> pArgumentName <*> pDefault
    <|> ArgNonOpt   <$> (pType <* pSpaces) <*> (pModifier Ellipsis "...") <*> (pSpaces *> pArgumentName)

pArgumentName :: MyParser ArgumentName
pArgumentName = try (ArgKey <$> pArgumentNameKeyword)
            <|> ArgIdent <$> pIdent

pArgumentNameKeyword :: MyParser ArgumentNameKeyword
pArgumentNameKeyword =  string "attribute" *> return ArgAttribute
                    <|> string "callback" *> return ArgCallback
                    <|> string "const" *> return ArgConst
                    <|> string "creator" *> return ArgCreator
                    <|> string "deleter" *> return ArgDeleter
                    <|> string "dictionary" *> return ArgDictionary
                    <|> string "enum" *> return ArgEnum
                    <|> string "exception" *> return ArgException  
                    <|> string "getter" *> return ArgGetter
                    <|> string "implements" *> return ArgImplements
                    <|> string "inherit" *> return ArgInherit
                    <|> string "interface" *> return ArgInterface  
                    <|> string "legacycaller" *> return ArgLegacycaller
                    <|> string "partial" *> return ArgPartial
                    <|> string "setter" *> return ArgSetter
                    <|> string "static" *> return ArgStatic 
                    <|> string "stringifier" *> return ArgStringifier
                    <|> string "typedef" *> return ArgTypedef
                    <|> string "unrestricted" *> return ArgUnrestricted

pDefault :: MyParser Default
pDefault =  DefaultValue <$> pConstValue
        <|> DefaultString <$> stringLit


pQualifier :: MyParser (Maybe Qualifier)
pQualifier =  try (string "static" *> return (Just QuaStatic))
          <|> try (Just . QSpecials <$> many pSpecial)
          <|> return Nothing

pSpecial :: MyParser Special
pSpecial = string "getter" *> return Getter
       <|> string "setter" *> return Setter
       <|> string "ccreator" *> return Ccreator
       <|> string "deleter" *> return Deleter
       <|> string "legacycaller" *> return Legacycaller

pReturnType :: MyParser ReturnType
pReturnType = string "void" *> return RetVoid
          <|> RetType <$> pType

pConstValue :: MyParser ConstValue
pConstValue =  ConstBooleanLiteral <$> pBool
           <|> try (ConstFloatLiteral <$> pFloat)
           <|> ConstInteger <$> pInt
           <|> string "null" *> return ConstNull

pBool :: MyParser Bool
pBool =  string "true" *> return True
     <|> string "false" *> return False


pNull :: MyParser (Maybe Null)
pNull = optionMaybe (char '?' *> return Null)

pPrimTy :: MyParser PrimitiveType
pPrimTy = try (string "boolean" *> return Boolean)
      <|> try (string "byte" *> return Byte)
      <|> try (string "octet" *> return Octet)
      <|> try (PrimIntegerType <$> pIntegerType)
      <|> PrimFloatType <$> pFloatType

pIntegerType :: MyParser IntegerType
pIntegerType = IntegerType <$> pUnsigned <* pSpaces <*> pIntegerWidth

pUnsigned :: MyParser (Maybe Unsigned)
pUnsigned = optionMaybe (string "unsigned" *> return Unsigned)

pIntegerWidth = string "short" *> return Short
             <|> Long . length <$> many1 (string "long" <* pSpaces)

pFloatType :: MyParser FloatType
pFloatType =  try (TyFloat <$> pModifier Unrestricted "unrestricted" <* spaces <* string "float")
          <|> TyDouble <$> pModifier Unrestricted "unrestricted" <* spaces <* string "double"

pType :: MyParser Type
pType =  TySingleType <$> pSingleType
     <|> TyUnionType <$> pUnionType <*> pTypeSuffix

pSingleType :: MyParser SingleType
pSingleType =  STyAny <$> (string "any" *> pTypeSuffix)
           <|> STyNonAny <$> pNonAnyType

pNonAnyType :: MyParser NonAnyType
pNonAnyType =  try (TyPrim <$> pPrimTy <*> pTypeSuffix)
           <|> TySequence <$> (string "sequence" *> pSpaces *> angles pType) <*> pNull
           <|> TyObject <$> (string "object" *> pTypeSuffix)
           <|> try (TyDOMString <$> (string "DOMString" *> pTypeSuffix))
           <|> TyDate <$> (string "Date" *> pTypeSuffix)
           <|> TyIdent <$> pIdent <*> pTypeSuffix

pTypeSuffix :: MyParser TypeSuffix
pTypeSuffix =  try (string "[]" *> return TypeSuffixArray)
           <|> try (char '?' *> return TypeSuffixNullable)
           <|> return TypeSuffixNone

-- FIXME: Not working correctly currently
pUnionType :: MyParser UnionType
pUnionType = parens (sepBy1 pUnionMemberType (string "or"))

pUnionMemberType :: MyParser UnionMemberType
pUnionMemberType =  UnionTy <$> pUnionType <*> pTypeSuffix
                <|> UnionTyNonAny <$> pNonAnyType
                <|> UnionTyAny <$> (string "any []" *> pTypeSuffix)

lexer = Tok.makeTokenParser emptyDef

parens     = Tok.parens lexer
braces     = Tok.braces lexer
angles     = Tok.angles lexer
reserved   = Tok.reserved lexer
reservedOp = Tok.reservedOp lexer
whiteSpace = Tok.whiteSpace lexer
pIdent     = Ident <$> Tok.identifier lexer
pInt       = Tok.integer lexer
pFloat     = Tok.float lexer
semi       = Tok.semi lexer
stringLit  = Tok.stringLiteral lexer
pEq        = char '='

pSpaces = try (skipMany (spaces *> pComment <* spaces) <* spaces)
      <|> spaces

pComment = try pLineComment <|> pBlockComment

pLineComment = do
  string "//"
  comment <- manyTill anyChar (try newline)
  modifyState (\ps -> ParserState { _comments = _comments ps ++ [comment]})

pBlockComment = do
  string "/*"
  comment <- manyTill anyChar (try (string "*/"))
  modifyState (\ps -> ParserState { _comments = _comments ps ++ lines comment})


getTag :: MyParser Tagging
getTag = do
  pos <- getPosition
  ParserState comments <- getState
  putState $ ParserState []
  return $ Tagging comments pos

