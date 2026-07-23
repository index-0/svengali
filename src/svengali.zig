// SPDX-License-Identifier: MPL-2.0
// Copyright (C) 2026 Alfredo Pérez

pub const arch = @import("arch.zig");
pub const mem = @import("mem.zig");
pub const process = @import("process.zig");
pub const procfs = @import("procfs.zig");

pub const Process = process.Process;
pub const Sg = process.Sg;
pub const Trace = process.Trace;
