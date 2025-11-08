// Copyright (c) 2025 Alfredo Pérez <index@mailbox.org>
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

const builtin = @import("builtin");

pub const Regs = switch (builtin.target.cpu.arch) {
    .x86 =>
        extern struct {
            bx: u32,
            cx: u32,
            dx: u32,
            si: u32,
            di: u32,
            bp: u32,
            ax: u32,
            ds: u16,
            __dsh: u16,
            es: u16,
            __esh: u16,
            fs: u16,
            __fsh: u16,
            gs: u16,
            __gsh: u16,
            orig_ax: u32,
            ip: u32,
            cs: u16,
            __csh: u16,
            flags: u32,
            sp: u32,
            ss: u16,
            __ssh: u16,
        },
    .x86_64 =>
        extern struct {
            r15: u64,
            r14: u64,
            r13: u64,
            r12: u64,
            bp: u64,
            bx: u64,
            r11: u64,
            r10: u64,
            r9: u64,
            r8: u64,
            ax: u64,
            cx: u64,
            dx: u64,
            si: u64,
            di: u64,
            orig_ax: u64,
            ip: u64,
            cs: u64,
            flags: u64,
            sp: u64,
            ss: u64,
        },
    else => @compileError("unsupported arch: " ++ builtin.target),
};
