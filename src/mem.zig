// Copyright (c) 2025 Alfredo Pérez <index@mailbox.org>
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Utilities for memory scanning and manipulation.

const std = @import("std");

/// Scatter/gather entry for memory addressing.
pub const Sg = struct {
    /// The base address for the memory operation.
    addr: usize,
    /// The data buffer associated with the operation.
    mem: []u8,
};

/// Initializes a new `CompareIterator` for a given type and operator.
pub fn findScalar(
    comptime T: type,
    comptime Op: std.math.CompareOperator,
    buf: []const T,
    val: T,
) CompareIterator(T, Op) {
    return .{
        .idx = 0,
        .buf = buf,
        .msk = 0,
        .val = val,
    };
}

test findScalar {
    const mem = &[_]u8{
        0xf1, 0x92, 0x34, 0x6b, 0xe1, 0x85, 0x65, 0x80,
        0x6d, 0x7b, 0xc3, 0x95, 0xa6, 0xcf, 0x76, 0x58,
        0x96, 0xd7, 0xdb, 0x98, 0xbb, 0x99, 0xe8, 0x83,
        0x28, 0xcb, 0x37, 0xde, 0xd6, 0x4b, 0xf6, 0xb1,
        0xe1, 0xab, 0xff, 0x79, 0x56, 0xb6, 0x63, 0x23,
        0x11,
    };

    {
        var it = findScalar(u8, .eq, mem, 0xe1);
        try std.testing.expectEqual(@as(?usize, 4), it.first());
        try std.testing.expectEqual(@as(?usize, 32), it.next());
        try std.testing.expectEqual(@as(?usize, null), it.next());
    }

    {
        var it = findScalar(u8, .gte, mem, 0xe0);
        try std.testing.expectEqual(@as(?usize, 0), it.first());
        try std.testing.expectEqual(@as(?usize, 4), it.next());
        try std.testing.expectEqual(@as(?usize, 22), it.next());
    }

    {
        const T: type = u64;
        const typed_mem = std.mem.bytesAsSlice(T, mem[0..(mem.len / @sizeOf(T)) * @sizeOf(T)]);
        var it = findScalar(T, .gte, @alignCast(typed_mem), 0x8300000000000000);
        try std.testing.expectEqual(@as(?usize, 2), it.first());
        try std.testing.expectEqual(@as(?usize, 3), it.next());
        try std.testing.expectEqual(@as(?usize, null), it.next());
    }
}

/// SIMD-accelerated comparison iterator to find indices of values in an aligned slice.
pub fn CompareIterator(comptime T: type, comptime Op: std.math.CompareOperator) type {
    const vec_len = std.simd.suggestVectorLength(T).?;
    const Vec = @Vector(vec_len, T);
    return struct {
        buf: []const T,
        idx: usize,
        val: T,

        msk: std.meta.Int(.unsigned, vec_len),

        const Self = @This();

        /// Finds the first match, use `next` to get all subsequent fields.
        /// Asserts that iteration has not begun and that we have an aligned slice.
        pub fn first(self: *Self) ?usize {
            std.debug.assert(self.idx == 0 and self.msk == 0);
            std.debug.assert(std.mem.isAligned(@intFromPtr(self.buf.ptr), @alignOf(T)));
            return self.next();
        }

        /// Finds the next index of a matching value. Returns null if no more matches.
        pub fn next(self: *Self) ?usize {
            if (self.msk != 0) {
                const ofs = @ctz(self.msk);
                self.msk &= (self.msk - 1);
                return self.idx + ofs - vec_len;
            }

            if (comptime (@typeInfo(T) == .int or @typeInfo(T) == .float) and
                std.math.isPowerOfTwo(@bitSizeOf(T)) and vec_len > 1)
            {
                const rhs: Vec = @splat(self.val);
                while (self.idx + vec_len <= self.buf.len) {
                    const lhs: Vec = self.buf[self.idx..][0..vec_len].*;
                    const res = compare(lhs, Op, rhs);
                    self.msk = @bitCast(res);
                    self.idx += vec_len;
                    if (self.msk != 0) {
                        const ofs = @ctz(self.msk);
                        self.msk &= (self.msk - 1);
                        return self.idx + ofs - vec_len;
                    }
                }
            }

            for (self.buf[self.idx..], self.idx..) |lhs, idx| {
                if (compare(lhs, Op, self.val)) {
                    self.idx = idx + 1;
                    return idx;
                }
            }

            self.idx = self.buf.len;
            return null;
        }

        /// Returns the remaining unprocessed portion of the slice.
        pub fn rest(self: *Self) []const T {
            if (self.msk != 0) {
                const start = self.idx + @ctz(self.msk) - vec_len;
                return self.buf[start..];
            }

            return self.buf[self.idx..];
        }

        /// Resets the iterator state.
        pub fn reset(self: *Self) void {
            self.idx = 0;
            self.msk = 0;
        }
    };
}

inline fn compare(a: anytype, comptime Op: std.math.CompareOperator, b: anytype) @TypeOf(a == b) {
    return switch (Op) {
        .lt => a < b,
        .lte => a <= b,
        .eq => a == b,
        .neq => a != b,
        .gt => a > b,
        .gte => a >= b,
    };
}
