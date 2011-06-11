{-# LANGUAGE NamedFieldPuns #-}

module Git.Index ( 
  open
  , add
  , addFile
  , remove
  , find
  , write
  , Index
  , Time(..)
  , Entry(..)    
  ) where

import qualified Git.Repository as Repository
import Foreign.ForeignPtr hiding (newForeignPtr)
import Foreign.Concurrent
import Foreign.Ptr
import Foreign.Marshal.Alloc
import Foreign.Storable
import Foreign.C.String
import Git.Result
import Data.Word
import Data.Int
import Git.Oid
import Git.Types
import Git.Error
import System.FilePath
import Control.Exception
import System.Posix.Types

import Bindings.Libgit2

data Index = Index { index::ForeignPtr C'git_index }
             deriving (Show, Eq)

data Time = Time { time_epoch::EpochTime, time_nsec::Word } 
            deriving (Show, Eq)

data Entry = Entry { entry_ctime::Time
                   , entry_mtime::Time
                   , entry_dev::Word
                   , entry_ino::Word
                   , entry_mode::Word
                   , entry_uid::Word
                   , entry_gid::Word
                   , entry_file_size::Word
                   , entry_oid::Oid
                   , entry_path::EntryName
                   }
             deriving (Show, Eq)

add::Index -> Entry -> IO ()
add index entry = withCIndex index $ \c'index -> withCEntry entry $ \c'entry ->  
  c'git_index_add2 c'index c'entry `wrap_git_result` return ()

type Stage = Int

addFile::Index -> EntryName -> Stage -> IO ()
addFile index name stage = withCIndex index $ \c'index ->
  withCString (entryName name) $ \c'name -> do 
    c'git_index_add c'index c'name (fromIntegral stage) `wrap_git_result` return ()

remove::Index -> EntryName -> IO ()
remove index name = withCIndex index $ \c'index ->
  withCString (entryName name) $ \c'name -> do
    result <- c'git_index_find c'index c'name
    if result < 0 then throwIO $ Error { error_explanation = "No entry in index with name: '" ++ entryName name ++ "'" 
                                       , error_code = 0
                                       }
      else c'git_index_remove c'index result `wrap_git_result` return ()
                     

find::Index -> EntryName -> IO (Maybe Entry)
find index (EntryName path) = withCIndex index $ \ c'index -> withCString path $ \c'path -> do
  result <- c'git_index_find c'index c'path
  if result < 0 then return Nothing
    else do
    ptr <- c'git_index_get c'index result
    if ptr == nullPtr then throwIO (IndexOutOfBounds "index out of bounds")
      else Just `fmap` fromCEntry ptr

open::Repository.Repository -> IO Index
open repo = Repository.withCRepository repo $ \c'repo -> 
  alloca $ \c'index -> do 
    c'git_index_open_inrepo c'index c'repo `wrap_git_result` (peek c'index >>= fromCIndex)

write::Index -> IO ()
write index = withCIndex index $ flip wrap_git_result (return ()) . c'git_index_write 

fromCIndex::Ptr C'git_index -> IO Index
fromCIndex c'index = fmap Index $ newForeignPtr c'index $ c'git_index_free c'index 

withCIndex::Index -> (Ptr C'git_index -> IO a) -> IO a
withCIndex Index { index } c = withForeignPtr index c

withCIndexTime::Time -> C'git_index_time
withCIndexTime Time { time_epoch, time_nsec } = C'git_index_time time_epoch (fromIntegral time_nsec)

fromCIndexTime::C'git_index_time -> Time
fromCIndexTime (C'git_index_time sec nsec) = Time { time_epoch = sec, time_nsec = fromIntegral nsec }

fromCEntry::Ptr C'git_index_entry -> IO Entry
fromCEntry c'entry = peek c'entry >>= go
  where 
    go (C'git_index_entry ctime mtime dev ino mode uid gid file_size c'oid flags flags_x c'path) = do 
      h'oid <- fromCOidStruct c'oid
      h'path <- EntryName `fmap` peekCString c'path
      return $ Entry (fromCIndexTime ctime) (fromCIndexTime mtime) (fromIntegral dev) 
        (fromIntegral ino) (fromIntegral mode) (fromIntegral uid) (fromIntegral gid) 
        (fromIntegral file_size) h'oid  h'path

withCEntry::Entry -> (Ptr C'git_index_entry -> IO a) -> IO a
withCEntry Entry { entry_ctime
                 , entry_mtime
                 , entry_dev
                 , entry_ino
                 , entry_mode
                 , entry_uid
                 , entry_gid
                 , entry_file_size
                 , entry_oid
                 , entry_path
                 } c = 
  withCString (entryName entry_path) $ \c'path -> do
    withCOid entry_oid $ \ p'oid -> do
      alloca $ \c'index -> do
        c'oid <- peek p'oid
        poke c'index $ C'git_index_entry 
         (withCIndexTime entry_ctime) (withCIndexTime entry_mtime) 
         (fromIntegral entry_dev) (fromIntegral entry_ino) (fromIntegral entry_mode) (fromIntegral entry_uid) 
         (fromIntegral entry_gid) (fromIntegral entry_file_size)
         c'oid 0 0 c'path
        c c'index
