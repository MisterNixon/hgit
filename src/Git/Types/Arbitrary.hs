module Git.Types.Arbitrary where
import Control.Applicative

import Git.Oid
import Git.Commit

import Test.QuickCheck hiding (Result)
import Test.QuickCheck.Property hiding (Result)

instance Arbitrary Oid where
  arbitrary = mkstr `fmap` vectorOf 40 arbitrary
  
instance Arbitrary TimeOffset where
  arbitrary = arbitrarySizedBoundedIntegral
  shrink (TimeOffset t) = filter inBounds $ map TimeOffset $ shrink t 
    where
      inBounds t = minBound <= t && t <= maxBound 
      
instance Arbitrary Signature where
  arbitrary = Signature <$> arbitraryString <*> arbitraryString <*> arbitrary
    where
      arbitraryString = listOf1 $ elements ['a'..'z']
  shrink (Signature author committer time) = Signature author committer `map` shrink time

instance Arbitrary Epoch where
  arbitrary = arbitrarySizedBoundedIntegral
  shrink (Epoch e) = filter inBounds $ map Epoch $ shrink e
    where
      inBounds t = minBound <= t && t <= maxBound

instance Arbitrary Time where  
  arbitrary = Time <$> arbitrary <*> arbitrary
  shrink (Time epoch offset) = (Time <$> pure epoch <*> shrink offset) ++ (Time <$> shrink epoch <*> pure offset)