// Copyright (c) 2025 Alfredo Pérez <index@mailbox.org>
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Utilities for interacting with the Linux procfs filesystem.

const std = @import("std");

/// Represents a single memory mapping entry from /proc/<pid>/maps.
pub const Map = struct {
    /// Start address of the mapping.
    start: usize,
    /// End address (exclusive) of the mapping.
    end: usize,
    /// Mapping permissions (read, write, execute, shared).
    perms: packed struct {
        r: bool,
        w: bool,
        x: bool,
        s: bool,
    },
    /// Offset into the mapped file.
    offset: usize,
    /// Device (major:minor) of the mapped file.
    device: packed struct (u32) {
        major: u16,
        minor: u16,
    },
    /// Inode of the mapped file.
    inode: usize,
    /// Pathname of the mapped file, or null for anonymous mappings.
    pathname: ?[]const u8,

    /// Returns the size (end - start) of the mapping in bytes.
    pub inline fn len(self: Map) usize {
        return self.end - self.start;
    }

    /// Frees the `pathname` slice (if non-null) using the allocator.
    pub inline fn deinit(self: Map, allocator: std.mem.Allocator) void {
        if (self.pathname) |p| {
            allocator.free(p);
        }
    }
};

/// An iterator that parses `Map` entries from a `std.fs.File.Reader`.
pub const MapIterator = struct {
    /// Allocator used for duplicating pathnames.
    allocator: std.mem.Allocator,
    /// The file reader to parse from.
    reader: std.fs.File.Reader,

    /// Initializes a new MapIterator with the given allocator and reader.
    pub fn init(allocator: std.mem.Allocator, reader: std.fs.File.Reader) MapIterator {
        return .{
            .allocator = allocator,
            .reader = reader,
        };
    }

    /// Attempts to parse the next `Map` entry from the reader.
    pub fn next(self: *MapIterator) !?Map {
        if (self.reader.interface.takeDelimiterInclusive('\n')) |line| {
            var idx: usize = 0;

            const start = try parseHex(usize, line, &idx);
            try expectChar(line, &idx, '-');
            const end = try parseHex(usize, line, &idx);
            try expectChar(line, &idx, ' ');
            if (idx + 4 >= line.len) return error.OutOfBounds;
            const perm_r = line[idx] == 'r'; idx += 1;
            const perm_w = line[idx] == 'w'; idx += 1;
            const perm_x = line[idx] == 'x'; idx += 1;
            const perm_s = line[idx] == 's' or line[idx] == 'S'; idx += 1;
            try expectChar(line, &idx, ' ');
            const offset = try parseHex(usize, line, &idx);
            try expectChar(line, &idx, ' ');
            const dev_major = try parseHex(u16, line, &idx);
            try expectChar(line, &idx, ':');
            const dev_minor = try parseHex(u16, line, &idx);
            try expectChar(line, &idx, ' ');
            const inode = try parseDec(usize, line, &idx);

            while (idx < line.len and line[idx] == ' ') idx += 1;

            var pathname: ?[]const u8 = null;
            if (idx < line.len and line[idx] != '\n') {
                const prev_idx: usize = idx;
                while (idx < line.len and line[idx] != '\n') idx += 1;
                while (idx > prev_idx and (line[idx - 1] == ' ' or line[idx - 1] == '\r')) idx -= 1;
                pathname = try self.allocator.dupe(u8, line[prev_idx..idx]);
            }

            return Map{
                .start = start,
                .end = end,
                .perms = .{ .r = perm_r, .w = perm_w, .x = perm_x, .s = perm_s },
                .offset = offset,
                .device = .{ .major = dev_major, .minor = dev_minor },
                .inode = inode,
                .pathname = pathname,
            };
        } else |err| {
            if (err != error.EndOfStream) return err;
        }

        return null;
    }
};

fn expectChar(line: []const u8, idx: *usize, expect: u8) !void {
    if (idx.* >= line.len) {
        return error.OutOfBounds;
    }

    if (line[idx.*] != expect) {
        return error.InvalidCharacter;
    }

    idx.* += 1;
}

fn parseHex(comptime T: type, line: []const u8, idx: *usize) !T {
    var out: T = 0;
    var j: usize = idx.*;
    const len = line.len;
    while (j < len) : (j += 1) {
        const c = line[j];
        if (!((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F'))) break;
        out = (out << 4) | @as(T, (c & 0xF) + ((c >> 6) * 9));
    }

    if (j == idx.*) return error.InvalidCharacter;

    idx.* = j;
    return out;
}

fn parseDec(comptime T: type, line: []const u8, idx: *usize) !T {
    var out: T = 0;
    var j: usize = idx.*;
    const len = line.len;
    while (j < len) : (j += 1) {
        const c = line[j];
        if (c < '0' or c > '9') break;
        out = out * 10 + @as(T, c - '0');
    }

    if (j == idx.*) return error.InvalidCharacter;

    idx.* = j;
    return out;
}
