const std = @import("std");
const debug = std.debug;

pub fn outer(arg: anytype) void {
    std.debug.print("outer = '{}'\n", .{@TypeOf(arg)});
    inner(arg);
}

pub fn inner(arg: []const []const isize) void {
    std.debug.print("inner = '{}'\n", .{@TypeOf(arg)});
}

pub fn main() void {
    const arg = [_][]const isize{ &.{ 0, 0 }, &.{ 0, 0 } };
    outer(arg[0..]);
    inner(arg[0..]);
}
