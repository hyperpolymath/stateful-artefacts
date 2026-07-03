-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
||| Artefact state record — typed lifecycle model (v0).
|||
||| The formal mirror of src/core/record.zig. The two state machines
||| (forward-only `Phase`; monotonic `Verification`) are encoded as typed
||| transition relations so that an *illegal* transition is unrepresentable —
||| there is simply no constructor for it. `stepPhase` / `stepVerification`
||| are the total boolean deciders that the Zig side mirrors.
|||
||| Enum numeric codes are STABLE and shared with the Zig core and the C header
||| (docs/spec/ARTEFACT-STATE-RECORD.adoc).

module Abi.Record

import System.FFI

%default total

--------------------------------------------------------------------------------
-- Enums (codes match the Zig enums and the C header)
--------------------------------------------------------------------------------

public export
data Phase = Draft | Built | Released | Superseded | Withdrawn

public export
phaseCode : Phase -> Bits8
phaseCode Draft = 0
phaseCode Built = 1
phaseCode Released = 2
phaseCode Superseded = 3
phaseCode Withdrawn = 4

public export
data Verification = Unverified | Verified | Rejected

public export
verificationCode : Verification -> Bits8
verificationCode Unverified = 0
verificationCode Verified = 1
verificationCode Rejected = 2

--------------------------------------------------------------------------------
-- Lifecycle: forward-only phase transitions (illegal edges unrepresentable)
--------------------------------------------------------------------------------

||| The relation of LEGAL phase transitions. There is exactly one constructor
||| per legal edge; no constructor mentions a backward edge or an edge out of a
||| terminal phase (Superseded, Withdrawn), so those transitions cannot be
||| constructed — the type system rules them out.
public export
data ValidPhaseStep : Phase -> Phase -> Type where
  DraftToBuilt        : ValidPhaseStep Draft Built
  DraftToWithdrawn    : ValidPhaseStep Draft Withdrawn
  BuiltToReleased     : ValidPhaseStep Built Released
  BuiltToWithdrawn    : ValidPhaseStep Built Withdrawn
  ReleasedToSuperseded : ValidPhaseStep Released Superseded
  ReleasedToWithdrawn : ValidPhaseStep Released Withdrawn

||| Total boolean decider, mirrored byte-for-byte by `phaseCanAdvance` in
||| src/core/record.zig.
public export
stepPhase : Phase -> Phase -> Bool
stepPhase Draft Built = True
stepPhase Draft Withdrawn = True
stepPhase Built Released = True
stepPhase Built Withdrawn = True
stepPhase Released Superseded = True
stepPhase Released Withdrawn = True
stepPhase _ _ = False

||| Soundness witnesses: each legal edge is inhabited in the relation.
public export
draftBuildsOk : ValidPhaseStep Draft Built
draftBuildsOk = DraftToBuilt

public export
releasedSupersededOk : ValidPhaseStep Released Superseded
releasedSupersededOk = ReleasedToSuperseded

||| Terminality: no phase transition leaves Withdrawn or Superseded (the
||| decider is constantly False from a terminal phase, for every target).
public export
withdrawnIsTerminal : (to : Phase) -> stepPhase Withdrawn to = False
withdrawnIsTerminal _ = Refl

public export
supersededIsTerminal : (to : Phase) -> stepPhase Superseded to = False
supersededIsTerminal _ = Refl

--------------------------------------------------------------------------------
-- Verification: monotonic — no silent regress to Unverified
--------------------------------------------------------------------------------

||| The relation of LEGAL `set-verification` transitions. No constructor
||| produces a target of `Unverified`: regressing to unverified is
||| unrepresentable here and only the explicit `reopen` operation (Zig
||| `stateful_artefacts_record_reopen_verification`) can do it.
public export
data ValidVerificationSet : Verification -> Verification -> Type where
  UnverifiedToVerified : ValidVerificationSet Unverified Verified
  UnverifiedToRejected : ValidVerificationSet Unverified Rejected
  VerifiedToRejected   : ValidVerificationSet Verified Rejected
  RejectedToVerified   : ValidVerificationSet Rejected Verified

||| Total boolean decider, mirrored by `verificationCanSet` in record.zig.
public export
stepVerification : Verification -> Verification -> Bool
stepVerification Unverified Verified = True
stepVerification Unverified Rejected = True
stepVerification Verified Rejected = True
stepVerification Rejected Verified = True
stepVerification _ _ = False

||| Monotonicity: `set-verification` never targets `Unverified` — the decider
||| is constantly False into Unverified, from every source state. The only path
||| back to Unverified is the explicit `reopen` operation.
public export
noSetToUnverified : (from : Verification) -> stepVerification from Unverified = False
noSetToUnverified Unverified = Refl
noSetToUnverified Verified = Refl
noSetToUnverified Rejected = Refl

--------------------------------------------------------------------------------
-- FFI to the record state machine (raw prims; declarations + parity).
-- Record creation/serialization stay on the Zig/C side for v0; these uniform
-- `AnyPtr -> [Int ->] PrimIO Int` bindings mirror the state-machine exports and
-- keep the Idris%foreign <-> Zig-export symbol set in lock-step
-- (tests/aspect_tests.sh).
--------------------------------------------------------------------------------

||| Current phase code (Phase), or -1 on null.
%foreign "C:stateful_artefacts_record_phase,libstateful_artefacts"
prim__recordPhase : AnyPtr -> PrimIO Int

||| Current verification code (Verification), or -1 on null.
%foreign "C:stateful_artefacts_record_verification,libstateful_artefacts"
prim__recordVerification : AnyPtr -> PrimIO Int

||| Advance the phase; returns a Result code (0 = ok, 2 = invalid_param).
%foreign "C:stateful_artefacts_record_advance_phase,libstateful_artefacts"
prim__recordAdvancePhase : AnyPtr -> Int -> PrimIO Int

||| Set verification; returns a Result code.
%foreign "C:stateful_artefacts_record_set_verification,libstateful_artefacts"
prim__recordSetVerification : AnyPtr -> Int -> PrimIO Int

||| Reopen verification (the only path back to Unverified); returns a Result code.
%foreign "C:stateful_artefacts_record_reopen_verification,libstateful_artefacts"
prim__recordReopenVerification : AnyPtr -> PrimIO Int
