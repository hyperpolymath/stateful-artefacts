// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// stateful-artefacts FFI integration tests
//
// These tests exercise the library through its C ABI: they declare the
// exported symbols with `extern fn` and are linked against the built
// libstateful_artefacts (see build.zig `test` step). This verifies the same
// boundary a C or Idris2 consumer sees, not the Zig internals.

const std = @import("std");

// Opaque handle at the C boundary (matches the Zig `Handle = opaque {}`).
const Handle = opaque {};

// Result codes (ADR-003 canon). At the C ABI this is a plain c_int.
const RESULT_OK: c_int = 0;
const RESULT_NULL_POINTER: c_int = 4;

extern fn stateful_artefacts_init() ?*Handle;
extern fn stateful_artefacts_free(?*Handle) void;
extern fn stateful_artefacts_process(?*Handle, u32) c_int;
extern fn stateful_artefacts_get_string(?*Handle) ?[*:0]const u8;
extern fn stateful_artefacts_free_string(?[*:0]const u8) void;
extern fn stateful_artefacts_last_error() ?[*:0]const u8;
extern fn stateful_artefacts_version() [*:0]const u8;
extern fn stateful_artefacts_is_initialized(?*Handle) u32;

// Artefact state record (v0)
const Record = opaque {};
const PHASE_DRAFT: c_int = 0;
const PHASE_BUILT: c_int = 1;
const PHASE_RELEASED: c_int = 2;
const VERIF_UNVERIFIED: c_int = 0;
const VERIF_VERIFIED: c_int = 1;
const RESULT_INVALID_PARAM: c_int = 2;
extern fn stateful_artefacts_record_new(?[*:0]const u8, c_int) ?*Record;
extern fn stateful_artefacts_record_free(?*Record) void;
extern fn stateful_artefacts_record_phase(?*Record) c_int;
extern fn stateful_artefacts_record_verification(?*Record) c_int;
extern fn stateful_artefacts_record_advance_phase(?*Record, c_int) c_int;
extern fn stateful_artefacts_record_set_verification(?*Record, c_int) c_int;
extern fn stateful_artefacts_record_reopen_verification(?*Record) c_int;
extern fn stateful_artefacts_record_serialize(?*Record, ?[*]u8, usize) c_int;

test "lifecycle: create, query, destroy" {
    const handle = stateful_artefacts_init() orelse return error.InitFailed;
    defer stateful_artefacts_free(handle);
    try std.testing.expectEqual(@as(u32, 1), stateful_artefacts_is_initialized(handle));
}

test "operations: process with a valid handle returns ok" {
    const handle = stateful_artefacts_init() orelse return error.InitFailed;
    defer stateful_artefacts_free(handle);
    try std.testing.expectEqual(RESULT_OK, stateful_artefacts_process(handle, 42));
}

test "null-safety: guarded entry points do not crash on null" {
    // These are the memory-safety guarantees the library actually makes:
    // every exported function tolerates a null handle. (Double-free of a
    // *valid* handle is NOT guaranteed and is intentionally not tested.)
    stateful_artefacts_free(null);
    try std.testing.expectEqual(RESULT_NULL_POINTER, stateful_artefacts_process(null, 0));
    try std.testing.expectEqual(@as(u32, 0), stateful_artefacts_is_initialized(null));
    try std.testing.expect(stateful_artefacts_get_string(null) == null);

    // process(null) must have recorded an error message.
    try std.testing.expect(stateful_artefacts_last_error() != null);
}

test "strings: get and free a library-allocated string" {
    const handle = stateful_artefacts_init() orelse return error.InitFailed;
    defer stateful_artefacts_free(handle);

    const str = stateful_artefacts_get_string(handle) orelse return error.NullString;
    defer stateful_artefacts_free_string(str);
    try std.testing.expect(std.mem.span(str).len > 0);
}

test "version: returns a non-empty string" {
    const ver = std.mem.span(stateful_artefacts_version());
    try std.testing.expect(ver.len > 0);
}

// ── Artefact state record (v0), exercised through the C ABI ──────────────────

test "record: lifecycle phase advances forward only" {
    const rec = stateful_artefacts_record_new("art-1", 0) orelse return error.NewFailed;
    defer stateful_artefacts_record_free(rec);
    try std.testing.expectEqual(PHASE_DRAFT, stateful_artefacts_record_phase(rec));
    try std.testing.expectEqual(RESULT_OK, stateful_artefacts_record_advance_phase(rec, PHASE_BUILT));
    try std.testing.expectEqual(PHASE_BUILT, stateful_artefacts_record_phase(rec));
    // Skipping a phase (built -> released is legal; built -> draft is not):
    try std.testing.expectEqual(RESULT_INVALID_PARAM, stateful_artefacts_record_advance_phase(rec, PHASE_DRAFT));
    try std.testing.expectEqual(PHASE_BUILT, stateful_artefacts_record_phase(rec)); // unchanged
}

test "record: verification is monotonic (reopen is the only way back)" {
    const rec = stateful_artefacts_record_new("art-2", 0) orelse return error.NewFailed;
    defer stateful_artefacts_record_free(rec);
    try std.testing.expectEqual(RESULT_OK, stateful_artefacts_record_set_verification(rec, VERIF_VERIFIED));
    // Cannot silently regress to unverified:
    try std.testing.expectEqual(RESULT_INVALID_PARAM, stateful_artefacts_record_set_verification(rec, VERIF_UNVERIFIED));
    try std.testing.expectEqual(VERIF_VERIFIED, stateful_artefacts_record_verification(rec));
    // reopen is the explicit path back:
    try std.testing.expectEqual(RESULT_OK, stateful_artefacts_record_reopen_verification(rec));
    try std.testing.expectEqual(VERIF_UNVERIFIED, stateful_artefacts_record_verification(rec));
}

test "record: null-safety on the record entry points" {
    stateful_artefacts_record_free(null);
    try std.testing.expectEqual(@as(c_int, -1), stateful_artefacts_record_phase(null));
    try std.testing.expectEqual(RESULT_NULL_POINTER, stateful_artefacts_record_advance_phase(null, PHASE_BUILT));
    try std.testing.expect(stateful_artefacts_record_new(null, 0) == null);
    // invalid kind code is rejected:
    try std.testing.expect(stateful_artefacts_record_new("x", 99) == null);
}

test "record: serialize produces the v0 key=value form" {
    const rec = stateful_artefacts_record_new("art-3", 2) orelse return error.NewFailed;
    defer stateful_artefacts_record_free(rec);
    var buf: [512]u8 = undefined;
    const n = stateful_artefacts_record_serialize(rec, &buf, buf.len);
    try std.testing.expect(n > 0);
    const out = buf[0..@intCast(n)];
    try std.testing.expect(std.mem.indexOf(u8, out, "schema-version=1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "id=art-3\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "kind=2\n") != null);
}
