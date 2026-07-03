------------------------- MODULE ArtefactLifecycle -------------------------
(* SPDX-License-Identifier: MPL-2.0                                          *)
(* Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)                   *)
(*                                                                          *)
(* Lifecycle specification for a single artefact state record (v0).         *)
(* Human spec: docs/spec/ARTEFACT-STATE-RECORD.adoc. The two state machines *)
(* (forward-only `phase`; monotonic `verification`) and the additive-schema *)
(* rule are mirrored in src/core/record.zig and src/interface/Abi/Record.idr.*)
(*                                                                          *)
(* Check with TLC (no CONSTANTS required):                                  *)
(*   tlc ArtefactLifecycle.tla -config ArtefactLifecycle.cfg                 *)
(***************************************************************************)

EXTENDS Naturals

VARIABLES
    phase,          \* lifecycle phase
    verification,   \* verification status
    schemaVersion   \* record schema version (additive-only => non-decreasing)

vars == <<phase, verification, schemaVersion>>

Phases        == {"draft", "built", "released", "superseded", "withdrawn"}
Verifications == {"unverified", "verified", "rejected"}

\* Legal phase transitions (forward-only; terminal: superseded, withdrawn).
ValidPhaseStep(from, to) ==
    \/ from = "draft"    /\ to \in {"built", "withdrawn"}
    \/ from = "built"    /\ to \in {"released", "withdrawn"}
    \/ from = "released" /\ to \in {"superseded", "withdrawn"}

\* Legal set-verification transitions. NEVER targets "unverified": returning to
\* unverified is possible only via the explicit Reopen action below.
ValidVerificationSet(from, to) ==
    \/ from = "unverified" /\ to \in {"verified", "rejected"}
    \/ from = "verified"   /\ to = "rejected"
    \/ from = "rejected"   /\ to = "verified"

Init ==
    /\ phase = "draft"
    /\ verification = "unverified"
    /\ schemaVersion = 1

AdvancePhase ==
    /\ \E p \in Phases : ValidPhaseStep(phase, p) /\ phase' = p
    /\ UNCHANGED <<verification, schemaVersion>>

SetVerification ==
    /\ \E v \in Verifications : ValidVerificationSet(verification, v) /\ verification' = v
    /\ UNCHANGED <<phase, schemaVersion>>

\* The ONLY action that returns verification to "unverified".
Reopen ==
    /\ verification # "unverified"
    /\ verification' = "unverified"
    /\ UNCHANGED <<phase, schemaVersion>>

\* Schema may only grow (additive-only evolution / backward-readability).
BumpSchema ==
    /\ schemaVersion' = schemaVersion + 1
    /\ UNCHANGED <<phase, verification>>

Next == AdvancePhase \/ SetVerification \/ Reopen \/ BumpSchema

\* Weak fairness on SetVerification drives liveness (a verdict is reached).
Spec == Init /\ [][Next]_vars /\ WF_vars(SetVerification)

\* ---- SAFETY ----

TypeInvariant ==
    /\ phase \in Phases
    /\ verification \in Verifications
    /\ schemaVersion \in Nat

\* Phase never moves along an illegal (backward or out-of-terminal) edge.
PhaseForwardOnly ==
    [][ phase' # phase => ValidPhaseStep(phase, phase') ]_phase

\* Verification-monotonicity: any transition that lands on "unverified" IS the
\* explicit Reopen action — verification never silently regresses.
NoSilentUnverify ==
    [][ (verification' = "unverified" /\ verification # "unverified") => Reopen ]_vars

\* Additive-schema: the schema version never decreases (older records stay
\* readable by newer consumers).
AdditiveSchema ==
    [][ schemaVersion' >= schemaVersion ]_schemaVersion

\* ---- LIVENESS ----

\* Every record eventually reaches a verdict (verified or rejected).
EventualVerdict == <>(verification = "verified" \/ verification = "rejected")

\* ---- MODEL-CHECKING BOUND ----
\* BumpSchema makes schemaVersion unbounded; bound it so TLC's state space is
\* finite (used as a CONSTRAINT in ArtefactLifecycle.cfg).
SchemaBound == schemaVersion =< 3

============================================================================
