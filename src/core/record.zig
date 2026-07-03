// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// Artefact state record — v0 core (domain logic, no C exports).
//
// The C ABI wrappers live in src/interface/ffi/src/main.zig and call into this
// module; keep this file free of `export fn` so the domain stays in src/core
// and the ABI boundary stays in the interface layer.
//
// Spec: docs/spec/ARTEFACT-STATE-RECORD.adoc.
// Enum numeric codes are STABLE and mirror the Idris2 model + the C header.

const std = @import("std");

pub const SCHEMA_VERSION: u32 = 1;
pub const MAX_STR: usize = 255;

pub const Kind = enum(u8) { binary = 0, container = 1, dataset = 2, document = 3, other = 4 };
pub const Phase = enum(u8) { draft = 0, built = 1, released = 2, superseded = 3, withdrawn = 4 };
pub const Verification = enum(u8) { unverified = 0, verified = 1, rejected = 2 };

/// Bounded, inline string (no heap ownership — the record is a fixed struct).
pub const BStr = struct {
    buf: [MAX_STR]u8 = [_]u8{0} ** MAX_STR,
    len: usize = 0,

    pub fn set(self: *BStr, s: []const u8) error{TooLong}!void {
        if (s.len > MAX_STR) return error.TooLong;
        @memcpy(self.buf[0..s.len], s);
        self.len = s.len;
    }

    pub fn slice(self: *const BStr) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn isEmpty(self: *const BStr) bool {
        return self.len == 0;
    }
};

pub const Record = struct {
    schema_version: u32 = SCHEMA_VERSION,
    id: BStr = .{},
    kind: Kind = .other,
    source_ref: BStr = .{},
    produced_by: BStr = .{},
    timestamp: i64 = 0,
    signature_ref: BStr = .{}, // empty = none
    phase: Phase = .draft,
    verification: Verification = .unverified,
    evidence_ref: BStr = .{}, // empty = none

    pub fn init(id: []const u8, kind: Kind) error{TooLong}!Record {
        var r = Record{ .kind = kind };
        try r.id.set(id);
        return r;
    }
};

//==============================================================================
// Lifecycle state machine (phase) — forward-only.
//==============================================================================

/// True iff `from -> to` is a legal phase transition (see the spec). Terminal
/// phases (superseded, withdrawn) have no outgoing edges.
pub fn phaseCanAdvance(from: Phase, to: Phase) bool {
    return switch (from) {
        .draft => to == .built or to == .withdrawn,
        .built => to == .released or to == .withdrawn,
        .released => to == .superseded or to == .withdrawn,
        .superseded, .withdrawn => false,
    };
}

pub const PhaseError = error{IllegalTransition};

pub fn advancePhase(rec: *Record, to: Phase) PhaseError!void {
    if (!phaseCanAdvance(rec.phase, to)) return error.IllegalTransition;
    rec.phase = to;
}

//==============================================================================
// Verification state machine — monotonic (no silent regress to unverified).
//==============================================================================

/// True iff `set_verification(from -> to)` is allowed. Moving to `unverified`
/// is never allowed here — that requires the explicit `reopen`.
pub fn verificationCanSet(from: Verification, to: Verification) bool {
    if (to == .unverified) return false;
    return switch (from) {
        .unverified => to == .verified or to == .rejected,
        .verified => to == .rejected,
        .rejected => to == .verified,
    };
}

pub const VerificationError = error{IllegalTransition};

pub fn setVerification(rec: *Record, to: Verification) VerificationError!void {
    if (!verificationCanSet(rec.verification, to)) return error.IllegalTransition;
    rec.verification = to;
}

/// The ONLY path back to `unverified` — a deliberate re-assessment.
pub fn reopenVerification(rec: *Record) void {
    rec.verification = .unverified;
    rec.evidence_ref.len = 0;
}

//==============================================================================
// Serialization (v0) — deterministic key=value lines, fixed field order.
//==============================================================================

/// Serialize `rec` into `out`. Returns the number of bytes written, or
/// error.BufferTooSmall. Optional fields with empty values are omitted.
pub fn serialize(rec: *const Record, out: []u8) error{BufferTooSmall}!usize {
    var w = std.io.fixedBufferStream(out);
    const s = w.writer();
    s.print("schema-version={d}\n", .{rec.schema_version}) catch return error.BufferTooSmall;
    s.print("id={s}\n", .{rec.id.slice()}) catch return error.BufferTooSmall;
    s.print("kind={d}\n", .{@intFromEnum(rec.kind)}) catch return error.BufferTooSmall;
    s.print("source-ref={s}\n", .{rec.source_ref.slice()}) catch return error.BufferTooSmall;
    s.print("produced-by={s}\n", .{rec.produced_by.slice()}) catch return error.BufferTooSmall;
    s.print("timestamp={d}\n", .{rec.timestamp}) catch return error.BufferTooSmall;
    if (!rec.signature_ref.isEmpty())
        s.print("signature-ref={s}\n", .{rec.signature_ref.slice()}) catch return error.BufferTooSmall;
    s.print("phase={d}\n", .{@intFromEnum(rec.phase)}) catch return error.BufferTooSmall;
    s.print("verification={d}\n", .{@intFromEnum(rec.verification)}) catch return error.BufferTooSmall;
    if (!rec.evidence_ref.isEmpty())
        s.print("evidence-ref={s}\n", .{rec.evidence_ref.slice()}) catch return error.BufferTooSmall;
    return w.pos;
}

//==============================================================================
// Tests (domain-level; the C-ABI level is covered by integration_test.zig)
//==============================================================================

test "phase advances forward only" {
    try std.testing.expect(phaseCanAdvance(.draft, .built));
    try std.testing.expect(phaseCanAdvance(.released, .withdrawn));
    try std.testing.expect(!phaseCanAdvance(.built, .draft)); // no regress
    try std.testing.expect(!phaseCanAdvance(.superseded, .released)); // terminal
    try std.testing.expect(!phaseCanAdvance(.draft, .released)); // no skipping
}

test "advancePhase enforces legality" {
    var r = try Record.init("a", .binary);
    try advancePhase(&r, .built);
    try std.testing.expectEqual(Phase.built, r.phase);
    try std.testing.expectError(error.IllegalTransition, advancePhase(&r, .draft));
}

test "verification never silently regresses" {
    var r = try Record.init("a", .binary);
    try setVerification(&r, .verified);
    // Cannot go back to unverified via set:
    try std.testing.expectError(error.IllegalTransition, setVerification(&r, .unverified));
    // verified <-> rejected is allowed (evidence changed):
    try setVerification(&r, .rejected);
    try std.testing.expectEqual(Verification.rejected, r.verification);
    // reopen is the explicit path back:
    reopenVerification(&r);
    try std.testing.expectEqual(Verification.unverified, r.verification);
}

test "serialize is deterministic and omits empty optionals" {
    var r = try Record.init("art-1", .dataset);
    try r.source_ref.set("repo://x");
    try r.produced_by.set("ci");
    r.timestamp = 42;
    var buf: [512]u8 = undefined;
    const n = try serialize(&r, &buf);
    const expected =
        "schema-version=1\n" ++
        "id=art-1\n" ++
        "kind=2\n" ++
        "source-ref=repo://x\n" ++
        "produced-by=ci\n" ++
        "timestamp=42\n" ++
        "phase=0\n" ++
        "verification=0\n";
    try std.testing.expectEqualStrings(expected, buf[0..n]);
}
