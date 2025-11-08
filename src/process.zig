// Copyright (c) 2025 Alfredo Pérez <index@mailbox.org>
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

//! Defines the `Process` struct for memory I/O and `ptrace` control of a target Linux process.

const std = @import("std");

const arch = @import("arch.zig");
const mem = @import("mem.zig");

/// Represents a Linux process for memory I/O and tracing.
pub const Process = struct {
    /// Process identifier.
    pid: std.posix.pid_t,
    /// Provides process tracing and control capabilities.
    trace: Trace,

    /// Creates a Process handle for `pid`.
    /// Fails if the process does not exist or if we lack the neccesary permissions.
    pub fn init(pid: std.posix.pid_t) !Process {
        _ = try std.posix.kill(pid, 0);
        return .{ .pid = pid, .trace = Trace{} };
    }

    /// Reads from the process's virtual memory using scatter-gather I/O.
    /// Returns the number of bytes successfully read.
    /// A value less than the total requested size indicates a partial read,
    /// which occurs if an invalid address or protected memory is encountered.
    pub fn vmRead(self: *const Process, sg: []mem.Sg) !usize {
        const IOV_MAX = std.posix.IOV_MAX;

        var local: [IOV_MAX]std.posix.iovec = undefined;
        var remote: [IOV_MAX]std.posix.iovec_const = undefined;

        var res: usize = 0;
        const n: usize = (sg.len + IOV_MAX - 1) / IOV_MAX;
        for (0..n) |i| {
            const s: usize = i * IOV_MAX;
            const e: usize = @min(s + IOV_MAX, sg.len);
            const l: usize = e - s;

            for (sg[s..e], 0..) |v, j| {
                remote[j] = .{
                    .base = @ptrFromInt(v.addr),
                    .len = v.mem.len
                };
                local[j] = .{
                    .base = v.mem.ptr,
                    .len = v.mem.len
                };
            }

            const ret = std.os.linux.process_vm_readv(self.pid, local[0..l], remote[0..l], 0);
            switch (std.posix.E.init(ret)) {
                .SUCCESS => res += ret,
                .PERM => return error.AccessDenied,
                .SRCH => return error.ProcessNotFound,
                .NOMEM => return error.SystemResources,
                .FAULT => return error.BadAddress,
                .INVAL => return error.InvalidArgument,
                else => unreachable,
            }
        }

        return res;
    }

    /// Writes to the process's virtual memory using scatter-gather I/O.
    /// Returns the number of bytes successfully written.
    /// A value less than the total requested size indicates a partial write,
    /// which occurs if an invalid address or protected memory is encountered.
    pub fn vmWrite(self: *const Process, sg: []const mem.Sg) !usize {
        const IOV_MAX = std.posix.IOV_MAX;

        var local: [IOV_MAX]std.posix.iovec_const = undefined;
        var remote: [IOV_MAX]std.posix.iovec_const = undefined;

        var res: usize = 0;
        const n: usize = (sg.len + IOV_MAX - 1) / IOV_MAX;
        for (0..n) |i| {
            const s: usize = i * IOV_MAX;
            const e: usize = @min(s + IOV_MAX, sg.len);
            const l: usize = e - s;

            for (sg[s..e], 0..) |v, j| {
                remote[j] = .{
                    .base = @ptrFromInt(v.addr),
                    .len = v.mem.len
                };
                local[j] = .{
                    .base = v.mem.ptr,
                    .len = v.mem.len
                };
            }

            const ret = std.os.linux.process_vm_writev(self.pid, local[0..l], remote[0..l], 0);
            switch (std.posix.E.init(ret)) {
                .SUCCESS => res += ret,
                .PERM => return error.AccessDenied,
                .SRCH => return error.ProcessNotFound,
                .NOMEM => return error.SystemResources,
                .FAULT => return error.BadAddress,
                .INVAL => return error.InvalidArgument,
                else => unreachable,
            }
        }

        return res;
    }
};

/// Provides process tracing and control via ptrace.
const Trace = struct {
    inline fn parent(self: *const Trace) *const Process {
        return @as(*const Process, @alignCast(@fieldParentPtr("trace", self)));
    }

    /// Raw wrapper for the ptrace syscall.
    pub inline fn ptrace(self: *const Trace, req: u32, addr: usize, data: usize) !void {
        try std.posix.ptrace(req, self.parent().*.pid, addr, data);
    }

    /// Gets the general-purpose registers.
    pub fn getRegSet(self: *const Trace) !arch.ptrace.Regs {
        var regset: arch.ptrace.Regs = undefined;
        const iovec: std.posix.iovec = .{
            .base = @ptrCast(&regset),
            .len = @sizeOf(arch.ptrace.Regs)
        };
        try self.ptrace(std.os.linux.PTRACE.GETREGSET, 1, @intFromPtr(&iovec));
        return regset;
    }

    /// Sets the general-purpose registers.
    pub fn setRegSet(self: *const Trace, regset: *const arch.ptrace.Regs) !void {
        const iovec: std.posix.iovec_const = .{
            .base = @ptrCast(regset),
            .len = @sizeOf(arch.ptrace.Regs)
        };
        try self.ptrace(std.os.linux.PTRACE.SETREGSET, 1, @intFromPtr(&iovec));
    }

    /// Continues execution.
    pub fn cont(self: *const Trace, signal: usize) !void {
        try self.ptrace(std.os.linux.PTRACE.CONT, 0, signal);
    }

    /// Continues execution until the next syscall.
    pub fn syscall(self: *const Trace, signal: usize) !void {
        try self.ptrace(std.os.linux.PTRACE.SYSCALL, 0, signal);
    }

    /// Executes a single instruction.
    pub fn singleStep(self: *const Trace, signal: usize) !void {
        try self.ptrace(std.os.linux.PTRACE.SINGLESTEP, 0, signal);
    }

    /// Restarts the tracee and waits for a new ptrace event.
    pub fn listen(self: *const Trace) !void {
        try self.ptrace(std.os.linux.PTRACE.LISTEN, 0, 0);
    }

    /// Sends an interrupt and waits for the tracee to stop.
    pub fn interrupt(self: *const Trace) !void {
        try self.ptrace(std.os.linux.PTRACE.INTERRUPT, 0, 0);
        const res: std.posix.WaitPidResult = std.posix.waitpid(self.parent().*.pid, 0);
        if (!std.posix.W.IFSTOPPED(res.status)) return error.InvalidState;
    }

    /// Attaches to the process for tracing.
    pub fn seize(self: *const Trace, flags: u32) !void {
        try self.ptrace(std.os.linux.PTRACE.SEIZE, 0, flags);
    }

    /// Detaches from the process, allowing it to continue normally.
    pub fn detach(self: *const Trace) !void {
        try self.ptrace(std.os.linux.PTRACE.DETACH, 0, 0);
    }
};
