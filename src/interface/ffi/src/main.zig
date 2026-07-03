// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
// stateful_artefacts FFI Implementation
//
// This module implements the C-compatible FFI declared in
// src/interface/Abi/Foreign.idr. All types and layouts must match the
// Idris2 ABI definitions.
//

const std = @import("std");

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
