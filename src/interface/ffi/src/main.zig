// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// stateful_artefacts FFI Implementation
//
// This module implements the C-compatible FFI declared in
// src/interface/Abi/Foreign.idr. All types and layouts must match the
// Idris2 ABI definitions.
//

const std = @import("std");
const core = @import("core"); // src/core/record.zig — artefact-state-record domain

// Version information (keep in sync with project)
const VERSION = "0.1.0";
const BUILD_INFO = "stateful_artefacts built with Zig " ++ @import("builtin").zig_version_string;

/// Thread-local error storage. Only static string literals are stored,
/// so consumers must never free the pointer returned by last_error.
threadlocal var last_error: ?[*:0]const u8 = null;

/// Set the last error message (static literals only)
fn setError(msg: [*:0]const u8) void {
    last_error = msg;
}

/// Clear the last error
fn clearError() void {
    last_error = null;
}

//==============================================================================
// Core Types (must match src/interface/Abi/Types.idr)
//==============================================================================

/// Result codes (must match the Idris2 Result type — ADR-003 canon)
pub const Result = enum(c_int) {
    ok = 0,
    @"error" = 1,
    invalid_param = 2,
    out_of_memory = 3,
    null_pointer = 4,
};

/// Library handle: opaque at the C boundary (Zig opaque types cannot
/// carry fields), backed internally by HandleImpl.
pub const Handle = opaque {};

/// Internal state hidden from C
const HandleImpl = struct {
    allocator: std.mem.Allocator,
    initialized: bool,
    // Add your fields here
};

inline fn fromHandle(handle: *Handle) *HandleImpl {
    return @ptrCast(@alignCast(handle));
}

inline fn toHandle(impl: *HandleImpl) *Handle {
    return @ptrCast(impl);
}

//==============================================================================
// Library Lifecycle
//==============================================================================

/// Initialize the library
/// Returns a handle, or null on failure
export fn stateful_artefacts_init() ?*Handle {
    const allocator = std.heap.c_allocator;

    const impl = allocator.create(HandleImpl) catch {
        setError("Failed to allocate handle");
        return null;
    };

    // Initialize handle
    impl.* = .{
        .allocator = allocator,
        .initialized = true,
    };

    clearError();
    return toHandle(impl);
}

/// Free the library handle
export fn stateful_artefacts_free(handle: ?*Handle) void {
    const h = fromHandle(handle orelse return);
    const allocator = h.allocator;

    // Clean up resources
    h.initialized = false;

    allocator.destroy(h);
    clearError();
}

//==============================================================================
// Core Operations
//==============================================================================

/// Process data (example operation)
export fn stateful_artefacts_process(handle: ?*Handle, input: u32) Result {
    const h = fromHandle(handle orelse {
        setError("Null handle");
        return .null_pointer;
    });

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    // Example processing logic
    _ = input;

    clearError();
    return .ok;
}

//==============================================================================
// String Operations
//==============================================================================

/// Get a string result (example)
/// Caller must free the returned string
export fn stateful_artefacts_get_string(handle: ?*Handle) ?[*:0]const u8 {
    const h = fromHandle(handle orelse {
        setError("Null handle");
        return null;
    });

    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }

    // Example: allocate and return a string
    const result = h.allocator.dupeZ(u8, "Example result") catch {
        setError("Failed to allocate string");
        return null;
    };

    clearError();
    return result.ptr;
}

/// Free a string allocated by the library
export fn stateful_artefacts_free_string(str: ?[*:0]const u8) void {
    const s = str orelse return;
    const allocator = std.heap.c_allocator;

    const slice = std.mem.span(s);
    allocator.free(slice);
}

//==============================================================================
// Array/Buffer Operations
//==============================================================================

/// Process an array of data
export fn stateful_artefacts_process_array(
    handle: ?*Handle,
    buffer: ?[*]const u8,
    len: u32,
) Result {
    const h = fromHandle(handle orelse {
        setError("Null handle");
        return .null_pointer;
    });

    const buf = buffer orelse {
        setError("Null buffer");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    // Access the buffer
    const data = buf[0..len];
    _ = data;

    // Process data here

    clearError();
    return .ok;
}

//==============================================================================
// Error Handling
//==============================================================================

/// Get the last error message (static storage — do not free)
/// Returns null if no error
export fn stateful_artefacts_last_error() ?[*:0]const u8 {
    return last_error;
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the library version
export fn stateful_artefacts_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information
export fn stateful_artefacts_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Callback Support
//==============================================================================

/// Callback function type (C ABI)
pub const Callback = *const fn (u64, u32) callconv(.c) u32;

/// Register a callback
export fn stateful_artefacts_register_callback(
    handle: ?*Handle,
    callback: ?Callback,
) Result {
    const h = fromHandle(handle orelse {
        setError("Null handle");
        return .null_pointer;
    });

    const cb = callback orelse {
        setError("Null callback");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    // Store callback for later use
    _ = cb;

    clearError();
    return .ok;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// Check if handle is initialized
export fn stateful_artefacts_is_initialized(handle: ?*Handle) u32 {
    const h = fromHandle(handle orelse return 0);
    return if (h.initialized) 1 else 0;
}

//==============================================================================
// Artefact State Record (v0)
//
// Opaque record handle over core.Record (src/core/record.zig). The state-machine
// legality (forward-only phase; monotonic verification) is enforced in core;
// these wrappers translate to the C ABI and the Result canon.
// Spec: docs/spec/ARTEFACT-STATE-RECORD.adoc.
//==============================================================================

/// Opaque artefact-state-record handle at the C boundary.
pub const Record = opaque {};

inline fn fromRecord(rec: *Record) *core.Record {
    return @ptrCast(@alignCast(rec));
}
inline fn toRecord(rec: *core.Record) *Record {
    return @ptrCast(rec);
}

fn kindFromInt(v: c_int) ?core.Kind {
    return if (v >= 0 and v <= 4) @enumFromInt(@as(u8, @intCast(v))) else null;
}
fn phaseFromInt(v: c_int) ?core.Phase {
    return if (v >= 0 and v <= 4) @enumFromInt(@as(u8, @intCast(v))) else null;
}
fn verificationFromInt(v: c_int) ?core.Verification {
    return if (v >= 0 and v <= 2) @enumFromInt(@as(u8, @intCast(v))) else null;
}

/// Create a record with the given id and kind. Returns null on failure.
export fn stateful_artefacts_record_new(id: ?[*:0]const u8, kind: c_int) ?*Record {
    const id_ptr = id orelse {
        setError("Null id");
        return null;
    };
    const k = kindFromInt(kind) orelse {
        setError("Invalid kind");
        return null;
    };
    const allocator = std.heap.c_allocator;
    const impl = allocator.create(core.Record) catch {
        setError("Failed to allocate record");
        return null;
    };
    impl.* = core.Record.init(std.mem.span(id_ptr), k) catch {
        allocator.destroy(impl);
        setError("id too long");
        return null;
    };
    clearError();
    return toRecord(impl);
}

/// Free a record.
export fn stateful_artefacts_record_free(rec: ?*Record) void {
    const r = fromRecord(rec orelse return);
    std.heap.c_allocator.destroy(r);
    clearError();
}

/// Current lifecycle phase (Phase code), or -1 on null.
export fn stateful_artefacts_record_phase(rec: ?*Record) c_int {
    const r = fromRecord(rec orelse return -1);
    return @intFromEnum(r.phase);
}

/// Current verification status (Verification code), or -1 on null.
export fn stateful_artefacts_record_verification(rec: ?*Record) c_int {
    const r = fromRecord(rec orelse return -1);
    return @intFromEnum(r.verification);
}

/// Set provenance fields. Empty/short strings only (<= 255).
export fn stateful_artefacts_record_set_provenance(
    rec: ?*Record,
    source_ref: ?[*:0]const u8,
    produced_by: ?[*:0]const u8,
    timestamp: i64,
) Result {
    const r = fromRecord(rec orelse {
        setError("Null record");
        return .null_pointer;
    });
    if (source_ref) |p| r.source_ref.set(std.mem.span(p)) catch {
        setError("source-ref too long");
        return .invalid_param;
    };
    if (produced_by) |p| r.produced_by.set(std.mem.span(p)) catch {
        setError("produced-by too long");
        return .invalid_param;
    };
    r.timestamp = timestamp;
    clearError();
    return .ok;
}

/// Advance the lifecycle phase. Illegal (non-forward / terminal) transitions
/// return invalid_param and leave the record unchanged.
export fn stateful_artefacts_record_advance_phase(rec: ?*Record, to: c_int) Result {
    const r = fromRecord(rec orelse {
        setError("Null record");
        return .null_pointer;
    });
    const target = phaseFromInt(to) orelse {
        setError("Invalid phase code");
        return .invalid_param;
    };
    core.advancePhase(r, target) catch {
        setError("Illegal phase transition");
        return .invalid_param;
    };
    clearError();
    return .ok;
}

/// Set verification status. Regressing to `unverified` is refused here — use
/// stateful_artefacts_record_reopen_verification.
export fn stateful_artefacts_record_set_verification(rec: ?*Record, to: c_int) Result {
    const r = fromRecord(rec orelse {
        setError("Null record");
        return .null_pointer;
    });
    const target = verificationFromInt(to) orelse {
        setError("Invalid verification code");
        return .invalid_param;
    };
    core.setVerification(r, target) catch {
        setError("Illegal verification transition (use reopen to unverify)");
        return .invalid_param;
    };
    clearError();
    return .ok;
}

/// The only path back to `unverified` — a deliberate re-assessment.
export fn stateful_artefacts_record_reopen_verification(rec: ?*Record) Result {
    const r = fromRecord(rec orelse {
        setError("Null record");
        return .null_pointer;
    });
    core.reopenVerification(r);
    clearError();
    return .ok;
}

/// Serialize the record into `buf` (v0 key=value form). Returns the number of
/// bytes written, or -1 on null/too-small buffer.
export fn stateful_artefacts_record_serialize(rec: ?*Record, buf: ?[*]u8, len: usize) c_int {
    const r = fromRecord(rec orelse {
        setError("Null record");
        return -1;
    });
    const b = buf orelse {
        setError("Null buffer");
        return -1;
    };
    const n = core.serialize(r, b[0..len]) catch {
        setError("Buffer too small");
        return -1;
    };
    return @intCast(n);
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const handle = stateful_artefacts_init() orelse return error.InitFailed;
    defer stateful_artefacts_free(handle);

    try std.testing.expect(stateful_artefacts_is_initialized(handle) == 1);
}

test "error handling" {
    const result = stateful_artefacts_process(null, 0);
    try std.testing.expectEqual(Result.null_pointer, result);

    const err = stateful_artefacts_last_error();
    try std.testing.expect(err != null);
}

test "version" {
    const ver = stateful_artefacts_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}
