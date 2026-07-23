// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Alfredo Pérez

const std = @import("std");

pub const Perms = packed struct {
    r: bool,
    w: bool,
    x: bool,
    s: bool,
};

pub const Device = packed struct (u32) {
    major: u16,
    minor: u16,
};

pub const Map = struct {
    start: usize,
    end: usize,
    perms: Perms,
    offset: usize,
    device: Device,
    inode: usize,
    pathname: ?[]const u8,

    pub inline fn len(self: Map) usize {
        return self.end - self.start;
    }
};

pub fn maps(reader: *std.Io.Reader) MapIterator {
    return .{ .reader = reader };
}

pub const MapIterator = struct {
    reader: *std.Io.Reader,

    pub fn next(self: *MapIterator) !?Map {
        const line = self.reader.takeDelimiterInclusive('\n') catch |err| switch (err) {
            error.EndOfStream => return null,
            else => |e| return e,
        };
        var idx: usize = 0;
        const start = try int(usize, 16, line, &idx);
        try expectChar(line, &idx, '-');
        const end = try int(usize, 16, line, &idx);
        try expectChar(line, &idx, ' ');
        if (idx + 4 >= line.len) return error.OutOfBounds;
        const perms: Perms = .{
            .r = line[idx] == 'r',
            .w = line[idx + 1] == 'w',
            .x = line[idx + 2] == 'x',
            .s = line[idx + 3] == 's' or line[idx + 3] == 'S',
        };
        idx += 4;
        try expectChar(line, &idx, ' ');
        const offset = try int(usize, 16, line, &idx);
        try expectChar(line, &idx, ' ');
        const dev_major = try int(u16, 16, line, &idx);
        try expectChar(line, &idx, ':');
        const dev_minor = try int(u16, 16, line, &idx);
        try expectChar(line, &idx, ' ');
        const inode = try int(usize, 10, line, &idx);
        const rest = std.mem.trim(u8, line[idx..], " \r\n");

        return .{
            .start = start,
            .end = end,
            .perms = perms,
            .offset = offset,
            .device = .{ .major = dev_major, .minor = dev_minor },
            .inode = inode,
            .pathname = if (rest.len == 0) null else rest,
        };
    }
};

fn expectChar(line: []const u8, idx: *usize, expect: u8) !void {
    if (idx.* >= line.len) return error.OutOfBounds;
    if (line[idx.*] != expect) return error.InvalidCharacter;
    idx.* += 1;
}

fn int(comptime T: type, comptime base: u8, line: []const u8, idx: *usize) !T {
    const from = idx.*;
    while (idx.* < line.len and isBaseDigit(base, line[idx.*])) idx.* += 1;
    return std.fmt.parseInt(T, line[from..idx.*], base);
}

fn isBaseDigit(comptime base: u8, c: u8) bool {
    return switch (base) {
        16 => std.ascii.isHex(c),
        10 => std.ascii.isDigit(c),
        else => @compileError("unsupported base"),
    };
}
