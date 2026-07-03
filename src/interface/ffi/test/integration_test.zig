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
