-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
||| Foreign Function Interface Bridge
|||
||| This module defines the raw FFI calls and their safe wrappers,
||| implemented in the Zig FFI layer (src/interface/ffi/src/main.zig,
||| built as libstateful_artefacts). Every binding here must have a
||| matching `export fn stateful_artefacts_*` on the Zig side; the
||| aspect tests count both sides to keep them in lock-step.

module Abi.Foreign

import Abi.Types
import Abi.Layout
import System.FFI

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Raw FFI call to initialize the library
%foreign "C:stateful_artefacts_init,libstateful_artefacts"
prim__init : PrimIO Bits64

||| Raw FFI call to free library resources
%foreign "C:stateful_artefacts_free,libstateful_artefacts"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for initialization
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free h.ptr)

--------------------------------------------------------------------------------
-- Core Operations
--------------------------------------------------------------------------------

||| Raw FFI call for main processing. Returns a Result code (Ok = 0).
%foreign "C:stateful_artefacts_process,libstateful_artefacts"
prim__process : Bits64 -> Bits32 -> PrimIO Bits32

||| Raw FFI call for buffer processing. No safe wrapper yet: buffer
||| marshalling policy belongs to the domain layer (pending re-transfer).
%foreign "C:stateful_artefacts_process_array,libstateful_artefacts"
prim__processArray : Bits64 -> Ptr Bits8 -> Bits32 -> PrimIO Bits32

||| Safe wrapper with error decoding. Ok maps to Right (); every other
||| code maps to Left, with unknown codes conservatively read as Error.
export
process : Handle -> Bits32 -> IO (Either Result ())
process h input = do
  code <- primIO (prim__process h.ptr input)
  pure $ case resultFromCode code of
    Just Ok  => Right ()
    Just err => Left err
    Nothing  => Left Error

--------------------------------------------------------------------------------
-- Status and Metrics
--------------------------------------------------------------------------------

||| Get the current error description from the library (static storage,
||| do not free; null when no error is pending)
%foreign "C:stateful_artefacts_last_error,libstateful_artefacts"
prim__lastError : PrimIO (Ptr String)

||| Check whether a handle is initialized (1) or not (0)
%foreign "C:stateful_artefacts_is_initialized,libstateful_artefacts"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Null check for FFI string pointers. `prim__isNullAnyPtr` (System.FFI)
||| returns 1 for a null pointer, 0 otherwise.
isNullStr : Ptr String -> Bool
isNullStr p = prim__isNullAnyPtr (prim__forgetPtr p) /= 0

||| Safe wrapper: the library's pending error message, if any
export
lastError : IO (Maybe String)
lastError = do
  p <- primIO prim__lastError
  pure $ if isNullStr p then Nothing else Just (prim__getString p)

||| Safe wrapper: is the handle initialized?
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  v <- primIO (prim__isInitialized h.ptr)
  pure (v /= 0)

||| Detailed error string helper
export
errorDescription : Result -> String
errorDescription Ok = "Success"
errorDescription Error = "Generic error"
errorDescription InvalidParam = "Invalid parameter"
errorDescription OutOfMemory = "Out of memory"
errorDescription NullPointer = "Null pointer"

--------------------------------------------------------------------------------
-- Strings and Version Information
--------------------------------------------------------------------------------

||| Get a library-allocated string (must be freed via prim__freeString;
||| null on failure)
%foreign "C:stateful_artefacts_get_string,libstateful_artefacts"
prim__getResultString : Bits64 -> PrimIO (Ptr String)

||| Free a string allocated by the library
%foreign "C:stateful_artefacts_free_string,libstateful_artefacts"
prim__freeString : Ptr String -> PrimIO ()

||| Library version (static storage, do not free)
%foreign "C:stateful_artefacts_version,libstateful_artefacts"
prim__version : PrimIO String

||| Build information (static storage, do not free)
%foreign "C:stateful_artefacts_build_info,libstateful_artefacts"
prim__buildInfo : PrimIO String

||| Safe wrapper: copies the library string into an Idris string and
||| frees the C allocation before returning
export
getString : Handle -> IO (Maybe String)
getString h = do
  p <- primIO (prim__getResultString h.ptr)
  if isNullStr p
    then pure Nothing
    else do
      let s = prim__getString p
      primIO (prim__freeString p)
      pure (Just s)

||| Safe wrapper: library version string
export
version : IO String
version = primIO prim__version

||| Safe wrapper: build information string
export
buildInfo : IO String
buildInfo = primIO prim__buildInfo

--------------------------------------------------------------------------------
-- Callbacks
--------------------------------------------------------------------------------

-- stateful_artefacts_register_callback is deliberately not bound here:
-- passing Idris closures across the C boundary needs a callback-marshalling
-- policy that belongs to the domain layer (pending re-transfer). The Zig
-- export exists and is covered by the Zig integration tests.

--------------------------------------------------------------------------------
-- Documentation
--------------------------------------------------------------------------------

||| Summary of ABI safety properties:
||| 1. All functions are total (total keyword enforced).
||| 2. Pointers are verified non-null before being wrapped in Handle.
||| 3. Memory layouts are proven C-ABI compliant in Abi.Layout.
||| 4. FFI boundary uses explicitly tagged types from Abi.Types.
public export
abiSafetyGuarantees : String
abiSafetyGuarantees = "stateful-artefacts ABI: 4 proven safety properties for FFI integration"
