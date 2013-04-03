{-# LANGUAGE
	TemplateHaskell,
	TupleSections,
	PatternGuards,
	TypeSynonymInstances,
	FlexibleInstances #-}

module File.Binary.Quote (
	binary,
	Field(..),
	Binary(..),
--	fii, -- fiiBE,
--	tii, -- tiiBE,
	times
) where

import Prelude hiding (sequence)

import Language.Haskell.TH hiding (Type)
import Language.Haskell.TH.Quote
import Data.Traversable hiding (mapM)
import Data.Maybe
import qualified Data.ByteString.Lazy.Char8 as BSLC

import File.Binary.Parse
import File.Binary.Classes

import Data.Monoid

binary :: QuasiQuoter
binary = QuasiQuoter {
	quoteExp = undefined,
	quotePat = undefined,
	quoteType = undefined,
	quoteDec = mkHaskellTree . parse
 }

mkHaskellTree :: BinaryStructure -> DecsQ
mkHaskellTree bs = do
		d <- mkData bsn body
		i <- mkInst bsn argn typ body
		return $ d ++ [i]
	where
	bsn = bsName bs
	argn = bsArgName bs
	typ = bsArgType bs
	body = bsBody bs

mkInst :: Name -> Name -> TypeQ -> [BinaryStructureItem] -> DecQ
mkInst bsn argn typ body =
	instanceD (cxt []) (appT (conT ''Field) (conT bsn)) [
		tySynInstD ''FieldArgument [conT bsn] typ,
		reading "fromBinary" bsn argn body,
		writing "toBinary" argn body
	 ]

writing :: String -> Name -> [BinaryStructureItem] -> DecQ
writing name argn body = do
	arg <- newName "_arg"
	bs <- newName "_bs"
	let run = appE (varE 'mconcat) $ listE $ map
		(\bsi -> writeField bs arg argn (bytesOf bsi) (valueOf bsi)) body
	funD (mkName name)
		[clause [varP arg, varP bs] (normalB run) []]

writeField :: Name -> Name -> Name -> Expression -> Value -> ExpQ
writeField bs arg argn size (Constant (Left n)) =
	appsE [fiend', expression (varE bs) (varE arg) argn size,
		sigE (litE $ integerL $ fromIntegral n)
		(conT ''Int)]
	where
	fiend' = varE 'toBinary
writeField _ _ _ _ (Constant (Right s)) =
	appsE [varE 'fs, litE $ stringL s]
writeField bs arg argn bytes (Variable v) =
	fieldValueToStr bs arg argn bytes False $ getField bs v

fs :: Binary a => String -> a
fs = makeBinary . BSLC.pack

fieldValueToStr :: Name -> Name -> Name -> Expression -> Bool -> ExpQ -> ExpQ
fieldValueToStr bs arg argn size False =
	appE $ appE (varE 'toBinary) (expression (varE bs) (varE arg) argn size)
fieldValueToStr bs arg argn size True = \val ->
	appE (varE 'mconcat) $ appsE [
		varE 'map, appE (varE 'toBinary) (expression (varE bs) (varE arg) argn size), val]

reading :: String -> Name -> Name -> [BinaryStructureItem] -> DecQ
reading name bsn argn body = do
	arg <- newName "_arg"
	cs <- newName "cs1"
	ret <- newName "ret"
	funD (mkName name) [clause [varP arg, varP cs]
		(normalB $ mkLetRec ret $ mkBody bsn arg argn body cs) []]

mkLetRec :: Name -> (Name -> ExpQ) -> ExpQ
mkLetRec n f = do
	rest <- newName "rest"
	letE [valD (tupP [varP n, varP rest]) (normalB $ f n) []] $
		tupE [varE n, varE rest]

mkBody :: Name -> Name -> Name -> [BinaryStructureItem] -> Name -> Name -> ExpQ
mkBody bsn arg argn body cs ret = do
	namePairs <- for names $ \n -> return . (n ,) =<< newName "tmp"
	(defs, rest) <- gather cs body $ mkDef namePairs
	letE (map return defs) $ tupE
		[recConE bsn (map toPair2 namePairs), varE rest]
	where
	names = variables $ map valueOf body
	toPair2 (n, nn) = return (n, VarE nn)
	mkDef :: [(Name, Name)] -> BinaryStructureItem -> Name -> Q ([Dec], Name)
	mkDef np item cs'
	    | Constant (Left val) <- valueOf item = do
		cs'' <- newName "cs"
		let	t = dropE' n $ varE cs'
			p = val `equal` appE (varE 'fst)
				(appE (appE (varE 'fromBinary) arg') $
					takeE' n $ varE cs')
			e = [e| error "bad value" |]
		d <- valD (varP cs'') (normalB $ condE p t e) []
		return ([d], cs'')
	    | Constant (Right val) <- valueOf item = do
		cs'' <- newName "cs"
		let t = dropE' n $ varE cs'
		let p = val `equal'` takeE' n (varE cs')
		let e = [e| error "bad value" |]
		d <- valD (varP cs'') (normalB $ condE p t e) []
		return ([d], cs'')
	    | Variable var <- valueOf item = do
		cs'' <- newName "cs"
		def <- valD (tupP [varP $ fromJust $ lookup var np, varP cs''])
			(normalB $ appE (appE (varE 'fromBinary) arg') $ varE cs') []
		return ([def], cs'')
	    | otherwise = error "bad"
	    where
	    n = expression (varE ret) (varE arg) argn $ bytesOf item
	    arg' = expression (varE ret) (varE arg) argn $ bytesOf item

getField :: Name -> Name -> ExpQ
getField bs v = appE (varE v) (varE bs)

equal :: Integer -> ExpQ -> ExpQ
equal x y = infixE (Just $ sigE (litE $ integerL x) (conT ''Integer))
	(varE '(==)) (Just y)

equal' :: String -> ExpQ -> ExpQ
equal' x y = infixE (Just $ litE $ stringL x) (varE '(==)) (Just y)

takeE' :: ExpQ -> ExpQ -> ExpQ
takeE' n xs = -- appE (varE 'ts) $ appsE [varE 'tk, n, xs]
	appE (varE 'BSLC.unpack) $ appE (varE 'fst) $ appsE [varE 'getBytes, n, xs]

dropE' :: ExpQ -> ExpQ -> ExpQ
dropE' n xs = appsE [varE 'dp, n, xs]

dp :: Binary a => Int -> a -> a
dp n = snd . getBytes n

gather :: Monad m => s -> [a] -> (a -> s -> m ([b], s)) -> m ([b], s)
gather s [] _ = return ([], s)
gather s (x : xs) f = do
	(ys, s') <- f x s
	(zs, s'') <- gather s' xs f
	return (ys ++ zs, s'')

mkData :: Name -> [BinaryStructureItem] -> DecsQ
mkData bsn body = do
	d <- dataD (cxt []) name [] [con] [''Show]
	return [d]
	where
	name = bsn
	con = recC bsn vsts

	vsts = flip map (filter isRight body) $ \item ->
		varStrictType (variable $ valueOf item) $
			strictType notStrict $ mkType False $ typeOf item
	isRight item
		| Variable _ <- valueOf item = True
		| otherwise = False

mkType :: Bool -> TypeQ -> TypeQ
mkType True t = appT listT $ mkType False t
mkType False typ = typ

times :: Int -> (s -> (ret, s)) -> s -> ([ret], s)
times 0 _ s = ([], s)
times n f s = let
	(ret, rest) = f s
	(rets, rest') = times (n - 1) f rest in
	(ret : rets, rest')
