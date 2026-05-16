//! Wraps an allocator and tracks current bytes, peak bytes, and total volume allocated.
const std = @import("std");
const Alignment = std.mem.Alignment;
const Allocator = std.mem.Allocator;

pub const TrackAllocator = struct {
    parent: Allocator,
    in_use: usize = 0,
    peak_in_use: usize = 0,
    total_allocated: usize = 0,

    const vtable: Allocator.VTable = .{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    pub fn init(parent: Allocator) TrackAllocator {
        return .{ .parent = parent };
    }

    pub fn allocator(self: *TrackAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    pub fn resetStats(self: *TrackAllocator) void {
        self.in_use = 0;
        self.peak_in_use = 0;
        self.total_allocated = 0;
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        const self: *TrackAllocator = @ptrCast(@alignCast(ctx));
        const result = self.parent.vtable.alloc(self.parent.ptr, len, alignment, ret_addr) orelse return null;
        self.in_use += len;
        self.total_allocated += len;
        self.peak_in_use = @max(self.peak_in_use, self.in_use);
        return result;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *TrackAllocator = @ptrCast(@alignCast(ctx));
        const ok = self.parent.vtable.resize(self.parent.ptr, memory, alignment, new_len, ret_addr);
        if (ok) {
            const old = memory.len;
            self.in_use = self.in_use - old + new_len;
            self.peak_in_use = @max(self.peak_in_use, self.in_use);
        }
        return ok;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *TrackAllocator = @ptrCast(@alignCast(ctx));
        const result = self.parent.vtable.remap(self.parent.ptr, memory, alignment, new_len, ret_addr);
        if (result) |_| {
            const old = memory.len;
            self.in_use = self.in_use - old + new_len;
            self.peak_in_use = @max(self.peak_in_use, self.in_use);
        }
        return result;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
        const self: *TrackAllocator = @ptrCast(@alignCast(ctx));
        self.in_use -= memory.len;
        self.parent.vtable.free(self.parent.ptr, memory, alignment, ret_addr);
    }
};
