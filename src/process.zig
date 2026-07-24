// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Alfredo Pérez

const std = @import("std");
const arch = @import("arch.zig");

pub const Sg = struct {
    addr: usize,
    mem: []u8,
};

pub const VmError = error{
    AccessDenied,
    InvalidArgument,
    ProcessNotFound,
    SystemResources,
    Unexpected,
};

pub const Process = struct {
    pid: std.posix.pid_t,

    pub fn init(pid: std.posix.pid_t) !Process {
        try std.posix.kill(pid, @enumFromInt(0));
        return .{ .pid = pid };
    }

    pub fn trace(self: Process) Trace {
        return .{ .pid = self.pid };
    }

    pub fn stop(self: Process) std.posix.KillError!void {
        return std.posix.kill(self.pid, .STOP);
    }

    pub fn cont(self: Process) std.posix.KillError!void {
        return std.posix.kill(self.pid, .CONT);
    }

    pub fn vmRead(self: *const Process, sg: []const Sg) VmError!usize {
        return self.vm(.r, sg);
    }

    pub fn vmWrite(self: *const Process, sg: []const Sg) VmError!usize {
        return self.vm(.w, sg);
    }

    fn vm(self: *const Process, comptime dir: enum { r, w }, sg: []const Sg) VmError!usize {
        const IOV_MAX = std.posix.IOV_MAX;
        const Local = if (dir == .r) std.posix.iovec else std.posix.iovec_const;
        var local: [IOV_MAX]Local = undefined;
        var remote: [IOV_MAX]std.posix.iovec_const = undefined;
        var res: usize = 0;
        const n: usize = (sg.len + IOV_MAX - 1) / IOV_MAX;
        for (0..n) |i| {
            const s: usize = i * IOV_MAX;
            const e: usize = @min(s + IOV_MAX, sg.len);
            const l: usize = e - s;
            var want: usize = 0;
            for (sg[s..e], 0..) |v, j| {
                remote[j] = .{ .base = @ptrFromInt(v.addr), .len = v.mem.len };
                local[j] = .{ .base = v.mem.ptr, .len = v.mem.len };
                want += v.mem.len;
            }
            const ret = switch (dir) {
                .r => std.os.linux.process_vm_readv(self.pid, local[0..l], remote[0..l], 0),
                .w => std.os.linux.process_vm_writev(self.pid, local[0..l], remote[0..l], 0),
            };
            switch (std.os.linux.errno(ret)) {
                .SUCCESS => {
                    res += ret;
                    if (ret < want) return res;
                },
                .FAULT => return res,
                .PERM => return error.AccessDenied,
                .SRCH => return error.ProcessNotFound,
                .NOMEM => return error.SystemResources,
                .INVAL => return error.InvalidArgument,
                else => |err| return std.posix.unexpectedErrno(err),
            }
        }
        return res;
    }
};

pub const Trace = struct {
    pid: std.posix.pid_t,

    pub inline fn ptrace(self: Trace, req: u32, addr: usize, data: usize) !void {
        try std.posix.ptrace(req, self.pid, addr, data);
    }

    const NT_PRSTATUS = 1;

    pub fn getRegSet(self: Trace) !arch.Regs {
        var regset: arch.Regs = undefined;
        const iovec: std.posix.iovec = .{
            .base = @ptrCast(&regset),
            .len = @sizeOf(arch.Regs)
        };
        try self.ptrace(std.os.linux.PTRACE.GETREGSET, NT_PRSTATUS, @intFromPtr(&iovec));
        return regset;
    }

    pub fn setRegSet(self: Trace, regset: *const arch.Regs) !void {
        const iovec: std.posix.iovec_const = .{
            .base = @ptrCast(regset),
            .len = @sizeOf(arch.Regs)
        };
        try self.ptrace(std.os.linux.PTRACE.SETREGSET, NT_PRSTATUS, @intFromPtr(&iovec));
    }

    pub fn cont(self: Trace, signal: usize) !void {
        try self.ptrace(std.os.linux.PTRACE.CONT, 0, signal);
    }

    pub fn syscall(self: Trace, signal: usize) !void {
        try self.ptrace(std.os.linux.PTRACE.SYSCALL, 0, signal);
    }

    pub fn singleStep(self: Trace, signal: usize) !void {
        try self.ptrace(std.os.linux.PTRACE.SINGLESTEP, 0, signal);
    }

    pub fn listen(self: Trace) !void {
        try self.ptrace(std.os.linux.PTRACE.LISTEN, 0, 0);
    }

    pub fn interrupt(self: Trace) !void {
        try self.ptrace(std.os.linux.PTRACE.INTERRUPT, 0, 0);
        var status: u32 = 0;
        const ret = std.os.linux.waitpid(self.pid, &status, 0);
        switch (std.os.linux.errno(ret)) {
            .SUCCESS => {},
            else => |err| return std.posix.unexpectedErrno(err),
        }
        if (!std.os.linux.W.IFSTOPPED(status)) return error.InvalidState;
    }

    pub fn seize(self: Trace, flags: u32) !void {
        try self.ptrace(std.os.linux.PTRACE.SEIZE, 0, flags);
    }

    pub fn detach(self: Trace) !void {
        try self.ptrace(std.os.linux.PTRACE.DETACH, 0, 0);
    }
};
