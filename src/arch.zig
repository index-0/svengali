// Copyright (c) 2025 Alfredo Pérez <index@mailbox.org>
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

const builtin = @import("builtin");

pub const ptrace = switch (builtin.target.cpu.arch) {
    .x86, .x86_64 => @import("arch/x86/ptrace.zig"),
    else => @compileError("unsupported arch: " ++ builtin.target),
};
