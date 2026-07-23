// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Alfredo Pérez

const std = @import("std");

pub fn eq(old: anytype, new: anytype, a: anytype, b: anytype) @TypeOf(new == a) {
    _ = old;
    _ = b;
    return new == a;
}

pub fn gt(old: anytype, new: anytype, a: anytype, b: anytype) @TypeOf(new > a) {
    _ = old;
    _ = b;
    return new > a;
}

pub fn lt(old: anytype, new: anytype, a: anytype, b: anytype) @TypeOf(new < a) {
    _ = old;
    _ = b;
    return new < a;
}

pub fn neq(old: anytype, new: anytype, a: anytype, b: anytype) @TypeOf(new != a) {
    _ = old;
    _ = b;
    return new != a;
}

pub fn gte(old: anytype, new: anytype, a: anytype, b: anytype) @TypeOf(new >= a) {
    _ = old;
    _ = b;
    return new >= a;
}

pub fn lte(old: anytype, new: anytype, a: anytype, b: anytype) @TypeOf(new <= a) {
    _ = old;
    _ = b;
    return new <= a;
}

pub fn between(old: anytype, new: anytype, a: anytype, b: anytype) @TypeOf((new >= a) & (new <= b)) {
    _ = old;
    return (new >= a) & (new <= b);
}

pub fn outside(old: anytype, new: anytype, a: anytype, b: anytype) @TypeOf((new < a) | (new > b)) {
    _ = old;
    return (new < a) | (new > b);
}

pub fn increased(old: anytype, new: anytype, a: anytype, b: anytype) @TypeOf(new > old) {
    _ = a;
    _ = b;
    return new > old;
}

pub fn decreased(old: anytype, new: anytype, a: anytype, b: anytype) @TypeOf(new < old) {
    _ = a;
    _ = b;
    return new < old;
}

pub fn changed(old: anytype, new: anytype, a: anytype, b: anytype) @TypeOf(new != old) {
    _ = a;
    _ = b;
    return new != old;
}

pub fn unchanged(old: anytype, new: anytype, a: anytype, b: anytype) @TypeOf(new == old) {
    _ = a;
    _ = b;
    return new == old;
}

pub fn scan(comptime T: type, comptime pred: anytype,
        old: ?[]align(1) const T, new: []align(1) const T, a: T, b: T) Scan(T, pred) {
    return .{ .old = old, .new = new, .a = a, .b = b, .idx = 0, .mask = 0 };
}

pub fn Scan(comptime T: type, comptime pred: anytype) type {
    const vec_len = std.simd.suggestVectorLength(T) orelse 1;
    const Vector = @Vector(vec_len, T);
    const Mask = std.meta.Int(.unsigned, vec_len);
    return struct {
        old: ?[]align(1) const T,
        new: []align(1) const T,
        a: T,
        b: T,
        idx: usize,
        mask: Mask,
        const Self = @This();
        pub fn next(self: *Self) ?usize {
            if (self.mask != 0) {
                const lane = @ctz(self.mask);
                self.mask &= self.mask - 1;
                return self.idx + lane - vec_len;
            }
            const a: Vector = @splat(self.a);
            const b: Vector = @splat(self.b);
            while (self.idx + vec_len <= self.new.len) {
                const old: Vector = if (self.old) |old| old[self.idx..][0..vec_len].* else undefined;
                const new: Vector = self.new[self.idx..][0..vec_len].*;
                self.mask = @bitCast(pred(old, new, a, b));
                self.idx += vec_len;
                if (self.mask != 0) {
                    const lane = @ctz(self.mask);
                    self.mask &= self.mask - 1;
                    return self.idx + lane - vec_len;
                }
            }
            while (self.idx < self.new.len) : (self.idx += 1) {
                const old = if (self.old) |old| old[self.idx] else undefined;
                const new = self.new[self.idx];
                if (pred(old, new, self.a, self.b)) {
                    const hit = self.idx;
                    self.idx += 1;
                    return hit;
                }
            }
            return null;
        }
    };
}
