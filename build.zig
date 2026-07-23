// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Alfredo Pérez

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    _ = b.addModule("svengali", .{
        .root_source_file = b.path("src/svengali.zig"),
        .target = target,
    });
}
