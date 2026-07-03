// SPDX-License-Identifier: MPL-2.0
// Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
//
// FFI build graph (Zig 0.15.2+).
//
// Produces static and shared libstateful_artefacts from src/main.zig and wires
// two test steps:
//   zig build            -> build + install both library variants
//   zig build test       -> unit tests (in main.zig) + integration tests
//                           (test/integration_test.zig, linked against the
//                            static library through the C ABI)

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The library implementation. It uses std.heap.c_allocator, so it needs libc.
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const static_lib = b.addLibrary(.{
        .name = "stateful_artefacts",
        .root_module = lib_mod,
        .linkage = .static,
    });
    b.installArtifact(static_lib);

    const shared_lib = b.addLibrary(.{
        .name = "stateful_artefacts",
        .root_module = lib_mod,
        .linkage = .dynamic,
    });
    b.installArtifact(shared_lib);

    // ---- Tests ----
    const test_step = b.step("test", "Run unit and integration tests");

    // Unit tests live in main.zig itself.
    const unit_tests = b.addTest(.{ .root_module = lib_mod });
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);

    // Integration tests call the exported C symbols; link them against the
    // static library so the extern fns resolve.
    const it_mod = b.createModule(.{
        .root_source_file = b.path("test/integration_test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const integration_tests = b.addTest(.{ .root_module = it_mod });
    integration_tests.linkLibrary(static_lib);
    test_step.dependOn(&b.addRunArtifact(integration_tests).step);
}
