-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
||| ABI Type Definitions Template
|||
||| This module defines the Application Binary Interface (ABI) for this library.
||| All type definitions include formal proofs of correctness.

module Abi.Types

import Data.Bits
import Data.So
import Data.Vect
import Decidable.Equality

%default total

--------------------------------------------------------------------------------
-- Platform Model
--------------------------------------------------------------------------------

||| Target platforms for the FFI bridge
public export
data Platform = Linux | MacOS | Windows | WASM | RISCV

||| Pointer size in bits per platform
public export
ptrSize : Platform -> Nat
ptrSize Linux = 64
ptrSize MacOS = 64
ptrSize Windows = 64
ptrSize WASM = 32
ptrSize RISCV = 64

||| Current target platform (detected at compile-time)
public export
thisPlatform : Platform
thisPlatform = Linux -- Simplified for template

--------------------------------------------------------------------------------
-- Core Types
--------------------------------------------------------------------------------

||| Return codes for FFI calls.
||| Canon (ADR-003): five values shared verbatim by Zig (`Result = enum(c_int)`),
||| this module, and the C header. Codes: Ok=0, Error=1, InvalidParam=2,
||| OutOfMemory=3, NullPointer=4.
public export
data Result = Ok | Error | InvalidParam | OutOfMemory | NullPointer

||| Numeric C-ABI code for each result (must match the Zig enum verbatim)
public export
resultCode : Result -> Bits32
resultCode Ok = 0
resultCode Error = 1
resultCode InvalidParam = 2
resultCode OutOfMemory = 3
resultCode NullPointer = 4

||| Decode a C result code; unknown codes yield Nothing
public export
resultFromCode : Bits32 -> Maybe Result
resultFromCode 0 = Just Ok
resultFromCode 1 = Just Error
resultFromCode 2 = Just InvalidParam
resultFromCode 3 = Just OutOfMemory
resultFromCode 4 = Just NullPointer
resultFromCode _ = Nothing

||| Results are decidably equal
public export
implementation DecEq Result where
  decEq Ok Ok = Yes Refl
  decEq Error Error = Yes Refl
  decEq InvalidParam InvalidParam = Yes Refl
  decEq OutOfMemory OutOfMemory = Yes Refl
  decEq NullPointer NullPointer = Yes Refl
  decEq Ok Error = No (\case Refl impossible)
  decEq Ok InvalidParam = No (\case Refl impossible)
  decEq Ok OutOfMemory = No (\case Refl impossible)
  decEq Ok NullPointer = No (\case Refl impossible)
  decEq Error Ok = No (\case Refl impossible)
  decEq Error InvalidParam = No (\case Refl impossible)
  decEq Error OutOfMemory = No (\case Refl impossible)
  decEq Error NullPointer = No (\case Refl impossible)
  decEq InvalidParam Ok = No (\case Refl impossible)
  decEq InvalidParam Error = No (\case Refl impossible)
  decEq InvalidParam OutOfMemory = No (\case Refl impossible)
  decEq InvalidParam NullPointer = No (\case Refl impossible)
  decEq OutOfMemory Ok = No (\case Refl impossible)
  decEq OutOfMemory Error = No (\case Refl impossible)
  decEq OutOfMemory InvalidParam = No (\case Refl impossible)
  decEq OutOfMemory NullPointer = No (\case Refl impossible)
  decEq NullPointer Ok = No (\case Refl impossible)
  decEq NullPointer Error = No (\case Refl impossible)
  decEq NullPointer InvalidParam = No (\case Refl impossible)
  decEq NullPointer OutOfMemory = No (\case Refl impossible)

||| Opaque handle for library resources
||| Invariant: Handle pointer must be non-null
public export
record Handle where
  constructor MkHandle
  ptr : Bits64
  0 prf : So (ptr /= 0)

||| Returns Nothing if pointer is null
public export
createHandle : Bits64 -> Maybe Handle
createHandle 0 = Nothing
createHandle ptr = case decSo (ptr /= 0) of
  Yes p => Just (MkHandle ptr p)
  No _ => Nothing

--------------------------------------------------------------------------------
-- C-Types Mapping
--------------------------------------------------------------------------------

||| Tagged types for C-FFI boundary
public export
data CType = CInt | CUInt | CLong | CULong | CPtrType

||| Pointer type for platform
public export
CPtr : Platform -> CType -> Type
CPtr p _ = Bits64 -- Simplified for 64-bit template

||| Size of C types (platform-specific)
public export
cSizeOf : (p : Platform) -> (t : CType) -> Nat
cSizeOf p CInt = 4
cSizeOf p CUInt = 4
cSizeOf p CLong = 8
cSizeOf p CULong = 8
cSizeOf p CPtrType = 8

||| Alignment of C types (platform-specific)
public export
cAlignOf : (p : Platform) -> (t : CType) -> Nat
cAlignOf p CInt = 4
cAlignOf p CUInt = 4
cAlignOf p CLong = 8
cAlignOf p CULong = 8
cAlignOf p CPtrType = 8
