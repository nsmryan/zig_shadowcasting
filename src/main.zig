const std = @import("std");
const testing = std.testing;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

/// This Pos type is expected to be generate enough to allow the user
/// to cast into and out of their own type.
pub const Pos = struct {
    x: isize,
    y: isize,

    pub fn new(x: isize, y: isize) Pos {
        return Pos{ .x = x, .y = y };
    }
};

/// Compute FOV information for a given position using the shadow mapping algorithm.
///
/// This uses the is_blocking function pointer, which checks whether a given position is
/// blocked (such as by a wall), and is expected to capture some kind of grid
/// or map from the user.
///
/// The mark_visible function pointer provides the ability to collect visible tiles. This
/// may push them to a vector, or modify the map, etc.
///
pub fn ComputeFov(comptime Map: type, comptime Result: type, comptime InErrorSet: type) type {
    return struct {
        const Self = @This();
        const ErrorSet = InErrorSet || error{Overflow};

        map: Map,
        result: Result,

        pub const IsBlocking = fn (pos: Pos, map: Map) bool;

        pub const MarkVisible = fn (pos: Pos, result: Result) ErrorSet!void;

        pub fn new(map: Map, result: Result) Self {
            return Self{ .map = map, .result = result };
        }

        pub fn compute_fov(self: *Self, origin: Pos, is_blocking: IsBlocking, mark_visible: MarkVisible) ErrorSet!void {
            try mark_visible(origin, self.result);

            //std.debug.print("\n", .{});
            var index: usize = 0;
            while (index < 4) : (index += 1) {
                const quadrant = Quadrant.new(Cardinal.from_index(index), origin);

                const first_row = Row.new(1, Rational.new(-1, 1), Rational.new(1, 1));

                try self.scan(first_row, quadrant, is_blocking, mark_visible);
            }
        }

        fn scan(self: *Self, input_row: Row, quadrant: Quadrant, is_blocking: IsBlocking, mark_visible: MarkVisible) ErrorSet!void {
            var prev_tile: ?Pos = null;

            var row = input_row;

            var iter: RowIter = row.tiles();
            //std.debug.print("s {}\n", .{input_row.depth});
            while (iter.next()) |tile| {
                //std.debug.print("r {} {}\n", .{ tile.x, tile.y });
                const tile_is_wall = is_blocking(quadrant.transform(tile), self.map);
                const tile_is_floor = !tile_is_wall;

                var prev_is_wall = false;
                var prev_is_floor = false;
                if (prev_tile) |prev| {
                    prev_is_wall = is_blocking(quadrant.transform(prev), self.map);
                    prev_is_floor = !prev_is_wall;
                }

                if (tile_is_wall or try is_symmetric(row, tile)) {
                    const pos = quadrant.transform(tile);

                    //std.debug.print("v {} {}\n", .{ pos.x, pos.y });

                    try mark_visible(pos, self.result);
                }

                if (prev_is_wall and tile_is_floor) {
                    row.start_slope = slope(tile);
                }

                if (prev_is_floor and tile_is_wall) {
                    var next_row = row.next();
                    next_row.end_slope = slope(tile);

                    try self.scan(next_row, quadrant, is_blocking, mark_visible);
                }

                prev_tile = tile;
            }

            if (prev_tile) |tile| {
                if (!is_blocking(quadrant.transform(tile), self.map)) {
                    try self.scan(row.next(), quadrant, is_blocking, mark_visible);
                }
            }
        }
    };
}

const Cardinal = enum {
    North,
    East,
    South,
    West,

    fn from_index(index: usize) Cardinal {
        const cardinals = [4]Cardinal{ Cardinal.North, Cardinal.East, Cardinal.South, Cardinal.West };
        return cardinals[index];
    }
};

const Quadrant = struct {
    cardinal: Cardinal,
    ox: isize,
    oy: isize,

    fn new(cardinal: Cardinal, origin: Pos) Quadrant {
        return Quadrant{ .cardinal = cardinal, .ox = origin.x, .oy = origin.y };
    }

    fn transform(self: *const Quadrant, tile: Pos) Pos {
        const row = tile.x;
        const col = tile.y;

        switch (self.cardinal) {
            Cardinal.North => {
                return Pos.new(self.ox + col, self.oy - row);
            },

            Cardinal.South => {
                return Pos.new(self.ox + col, self.oy + row);
            },

            Cardinal.East => {
                return Pos.new(self.ox + row, self.oy + col);
            },

            Cardinal.West => {
                return Pos.new(self.ox - row, self.oy + col);
            },
        }
    }
};

const Row = struct {
    depth: isize,
    start_slope: Rational,
    end_slope: Rational,

    fn new(depth: isize, start_slope: Rational, end_slope: Rational) Row {
        return .{ .depth = depth, .start_slope = start_slope, .end_slope = end_slope };
    }

    fn tiles(self: *Row) RowIter {
        const depth_times_start = Rational.new(self.depth, 1).mult(self.start_slope);
        const depth_times_end = Rational.new(self.depth, 1).mult(self.end_slope);

        const min_col = round_ties_up(depth_times_start);

        const max_col = round_ties_down(depth_times_end);

        const depth = self.depth;

        //std.debug.print("row iter {} {} {}", .{ min_col, max_col, depth });
        return RowIter.new(min_col, max_col, depth);
    }

    fn next(self: *Row) Row {
        return Row.new(self.depth + 1, self.start_slope, self.end_slope);
    }
};

const RowIter = struct {
    min_col: isize,
    max_col: isize,
    depth: isize,
    col: isize,

    pub fn new(min_col: isize, max_col: isize, depth: isize) RowIter {
        return RowIter{ .min_col = min_col, .max_col = max_col, .depth = depth, .col = min_col };
    }

    pub fn next(self: *RowIter) ?Pos {
        if (self.col > self.max_col) {
            return null;
        } else {
            const col = self.col;
            self.col += 1;
            return Pos.new(self.depth, col);
        }
    }
};

fn slope(tile: Pos) Rational {
    const row_depth = tile.x;
    const col = tile.y;
    return Rational.new(2 * col - 1, 2 * row_depth);
}

fn is_symmetric(row: Row, tile: Pos) error{Overflow}!bool {
    const col = tile.y;

    const depth_times_start = Rational.new(row.depth, 1).mult(row.start_slope);
    const depth_times_end = Rational.new(row.depth, 1).mult(row.end_slope);

    const col_rat = Rational.new(col, 1);

    const symmetric = (try col_rat.gteq(depth_times_start)) and (try col_rat.lteq(depth_times_end));

    return symmetric;
}

fn round_ties_up(n: Rational) isize {
    return (n.add(Rational.new(1, 2))).floor();
}

fn round_ties_down(n: Rational) isize {
    return (n.sub(Rational.new(1, 2))).ceil();
}

const Rational = struct {
    const Error = error{Overflow};
    num: isize,
    denom: isize,
    ratio: std.math.big.Rational,

    pub fn new(num: isize, denom: isize) Rational {
        var allocator = std.heap.GeneralPurposeAllocator(.{}){};
        var ratio = std.math.big.Rational.init(allocator.allocator()) catch unreachable;
        return Rational{ .num = num, .denom = denom, .ratio = ratio };
    }

    pub fn gteq(self: Rational, other: Rational) Rational.Error!bool {
        var allocator = std.heap.GeneralPurposeAllocator(.{}){};

        var first = std.math.big.Rational.init(allocator.allocator()) catch unreachable;
        first.setRatio(self.num, self.denom) catch unreachable;

        var second = std.math.big.Rational.init(allocator.allocator()) catch unreachable;
        second.setRatio(other.num, other.denom) catch unreachable;

        var result = ((self.num * other.denom)) >= ((other.num * self.denom));

        var ratio_comp = first.orderAbs(second) catch unreachable;

        if ((result and (ratio_comp == std.math.Order.lt)) or (!result and ratio_comp != std.math.Order.lt)) {
            std.debug.print("gteq gave different results\n", .{});
            std.debug.print("{}/{} >= {}/{} = {}\n", .{ self.num, self.denom, other.num, other.denom, result });
            std.debug.print("{} >= {} = {}\n", .{
                first.toFloat(f64) catch unreachable,
                second.toFloat(f64) catch unreachable,
                ratio_comp,
            });
            unreachable;
        }

        return result;
    }

    pub fn lteq(self: Rational, other: Rational) Rational.Error!bool {
        var allocator = std.heap.GeneralPurposeAllocator(.{}){};

        var first = std.math.big.Rational.init(allocator.allocator()) catch unreachable;
        first.setRatio(self.num, self.denom) catch unreachable;

        var second = std.math.big.Rational.init(allocator.allocator()) catch unreachable;
        second.setRatio(other.num, other.denom) catch unreachable;

        var result = ((self.num * other.denom)) <= ((other.num * self.denom));

        var ratio_comp = first.orderAbs(second) catch unreachable;

        if ((result and (ratio_comp == std.math.Order.gt)) or (!result and ratio_comp != std.math.Order.gt)) {
            std.debug.print("lteq gave different results\n", .{});
            std.debug.print("{}/{} <= {}/{} = {}\n", .{ self.num, self.denom, other.num, other.denom, result });
            unreachable;
        }

        return result;
    }

    pub fn mult(self: Rational, other: Rational) Rational {
        var allocator = std.heap.GeneralPurposeAllocator(.{}){};

        var first = std.math.big.Rational.init(allocator.allocator()) catch unreachable;
        first.setRatio(self.num, self.denom) catch unreachable;

        var second = std.math.big.Rational.init(allocator.allocator()) catch unreachable;
        second.setRatio(other.num, other.denom) catch unreachable;

        var result = Rational.new(self.num * other.num, self.denom * other.denom);

        var ratio_result = std.math.big.Rational.init(allocator.allocator()) catch unreachable;
        ratio_result.mul(first, second) catch unreachable;

        var result_as_ratio = std.math.big.Rational.init(allocator.allocator()) catch unreachable;
        result_as_ratio.setRatio(result.num, result.denom) catch unreachable;

        if (ratio_result.order(result_as_ratio) catch unreachable != std.math.Order.eq) {
            std.debug.print("mult gave different results\n", .{});
            std.debug.print("{}/{} * {}/{} = {}/{}\n", .{ self.num, self.denom, other.num, other.denom, result.num, result.denom });
            std.debug.print("{} * {} = {}\n", .{
                first.toFloat(f64) catch unreachable,
                second.toFloat(f64) catch unreachable,
                result_as_ratio.toFloat(f64) catch unreachable,
            });
            unreachable;
        }

        return result;
    }

    pub fn add(self: Rational, other: Rational) Rational {
        var allocator = std.heap.GeneralPurposeAllocator(.{}){};

        var first = std.math.big.Rational.init(allocator.allocator()) catch unreachable;
        first.setRatio(self.num, self.denom) catch unreachable;

        var second = std.math.big.Rational.init(allocator.allocator()) catch unreachable;
        second.setRatio(other.num, other.denom) catch unreachable;

        var result = Rational.new(self.num * other.denom + other.num * self.denom, self.denom * other.denom);

        var ratio_result = std.math.big.Rational.init(allocator.allocator()) catch unreachable;
        ratio_result.add(first, second) catch unreachable;

        var result_as_ratio = std.math.big.Rational.init(allocator.allocator()) catch unreachable;
        result_as_ratio.setRatio(result.num, result.denom) catch unreachable;

        if (ratio_result.order(result_as_ratio) catch unreachable != std.math.Order.eq) {
            std.debug.print("add gave different results\n", .{});
            std.debug.print("{}/{} + {}/{} = {}/{}\n", .{ self.num, self.denom, other.num, other.denom, result.num, result.denom });
            std.debug.print("{} + {} = {}\n", .{
                first.toFloat(f64) catch unreachable,
                second.toFloat(f64) catch unreachable,
                result_as_ratio.toFloat(f64) catch unreachable,
            });
            unreachable;
        }

        return result;
    }

    pub fn sub(self: Rational, other: Rational) Rational {
        var allocator = std.heap.GeneralPurposeAllocator(.{}){};

        var first = std.math.big.Rational.init(allocator.allocator()) catch unreachable;
        first.setRatio(self.num, self.denom) catch unreachable;

        var second = std.math.big.Rational.init(allocator.allocator()) catch unreachable;
        second.setRatio(other.num, other.denom) catch unreachable;

        var result = Rational.new(self.num * other.denom - other.num * self.denom, self.denom * other.denom);

        var ratio_result = std.math.big.Rational.init(allocator.allocator()) catch unreachable;
        ratio_result.sub(first, second) catch unreachable;

        var result_as_ratio = std.math.big.Rational.init(allocator.allocator()) catch unreachable;
        result_as_ratio.setRatio(result.num, result.denom) catch unreachable;

        if (ratio_result.order(result_as_ratio) catch unreachable != std.math.Order.eq) {
            std.debug.print("sub gave different results\n", .{});
            std.debug.print("{}/{} - {}/{} = {}/{}\n", .{ self.num, self.denom, other.num, other.denom, result.num, result.denom });
            std.debug.print("{} - {} = {}\n", .{
                first.toFloat(f64) catch unreachable,
                second.toFloat(f64) catch unreachable,
                result_as_ratio.toFloat(f64) catch unreachable,
            });
            unreachable;
        }

        return result;
    }

    pub fn ceil(self: Rational) isize {
        if (self.denom != 0) {
            const div = @divFloor(self.num, self.denom);
            var result = div + @boolToInt(@mod(self.num, self.denom) > 0);

            var allocator = std.heap.GeneralPurposeAllocator(.{}){};
            var ratio = std.math.big.Rational.init(allocator.allocator()) catch unreachable;
            ratio.setRatio(self.num, self.denom) catch unreachable;
            var ratio_result = @ceil(ratio.toFloat(f64) catch unreachable);
            if (@floatToInt(isize, ratio_result) != result) {
                std.debug.print("ratio ceil {}, Rational was {}\n", .{ ratio_result, result });
                unreachable;
            }

            return result;
        } else {
            // Idk whether this can happen for this algorithm.
            return 0;
        }
    }

    pub fn floor(self: Rational) isize {
        if (self.denom != 0) {
            var result = @divFloor(self.num, self.denom);

            var allocator = std.heap.GeneralPurposeAllocator(.{}){};
            var ratio = std.math.big.Rational.init(allocator.allocator()) catch unreachable;
            ratio.setRatio(self.num, self.denom) catch unreachable;
            var ratio_result = @floor(ratio.toFloat(f64) catch unreachable);
            if (@floatToInt(isize, ratio_result) != result) {
                std.debug.print("ratio floor {}, Rational was {}\n", .{ ratio_result, result });
                unreachable;
            }

            return result;
        } else {
            // Idk whether this can happen for this algorithm.
            return 0;
        }
    }

    pub fn eq(self: Rational, other: Rational) bool {
        return self.num == other.num and self.denom == other.denom;
    }
};

test "Rational ceil" {
    try std.testing.expectEqual(@as(isize, 1), Rational.new(1, 2).ceil());
    try std.testing.expectEqual(@as(isize, 1), Rational.new(1, 1).ceil());
    try std.testing.expectEqual(@as(isize, 0), Rational.new(1, 0).ceil());
}

test "Rational floor" {
    try std.testing.expectEqual(@as(isize, 0), Rational.new(1, 2).floor());
    try std.testing.expectEqual(@as(isize, 1), Rational.new(1, 1).floor());
    try std.testing.expectEqual(@as(isize, 0), Rational.new(1, 0).floor());
}

test "Rational mult" {
    try std.testing.expect(Rational.new(1, 4).eq(Rational.new(1, 2).mult(Rational.new(1, 2))));
    try std.testing.expect(Rational.new(4, 9).eq(Rational.new(2, 3).mult(Rational.new(2, 3))));
}

fn inside_map(pos: Pos, map: []const []const isize) bool {
    const is_inside = @bitCast(usize, pos.y) < map.len and @bitCast(usize, pos.x) < map[0].len;
    return is_inside;
}

fn matching_visible(expected: []const []const isize, visible: ArrayList(Pos)) !void {
    std.debug.print("\nactual\n", .{});
    var y: usize = 0;
    while (y < expected.len) : (y += 1) {
        var x: usize = 0;
        while (x < expected[0].len) : (x += 1) {
            if (contains(visible, Pos.new(@intCast(isize, x), @intCast(isize, y)))) {
                std.debug.print("1 ", .{});
            } else {
                std.debug.print("0 ", .{});
            }
            //std.debug.assert(expected[y][x] == 1 and contains(visible, Pos.new(@bitCast(isize, x), @bitCast(isize, y))));
        }
        std.debug.print("\n", .{});
    }

    std.debug.print("\nexpected\n", .{});
    y = 0;
    while (y < expected.len) : (y += 1) {
        var x: usize = 0;
        while (x < expected[0].len) : (x += 1) {
            if (expected[y][x] == 1) {
                std.debug.print("1 ", .{});
            } else {
                std.debug.print("0 ", .{});
            }
            //std.debug.assert(expected[y][x] == 1 and contains(visible, Pos.new(@bitCast(isize, x), @bitCast(isize, y))));
        }
        std.debug.print("\n", .{});
    }

    y = 0;
    while (y < expected.len) : (y += 1) {
        var x: usize = 0;
        while (x < expected[0].len) : (x += 1) {
            std.debug.print("{} {} = {}, {}\n", .{ x, y, expected[y][x], contains(visible, Pos.new(@bitCast(isize, x), @bitCast(isize, y))) });
            try std.testing.expectEqual(expected[y][x] == 1, contains(visible, Pos.new(@bitCast(isize, x), @bitCast(isize, y))));
        }
    }
}

fn is_blocking_fn(pos: Pos, tiles: []const []const isize) bool {
    return !inside_map(pos, tiles) or tiles[@intCast(usize, pos.y)][@intCast(usize, pos.x)] == 1;
}

const State = struct {
    visible: ArrayList(Pos),
    tiles: []const []const isize,

    pub fn new(visible: ArrayList(Pos), tiles: []const []const isize) State {
        return State{ .visible = visible, .tiles = tiles };
    }
};

fn contains(visible: ArrayList(Pos), pos: Pos) bool {
    for (visible.items[0..]) |item| {
        if (std.meta.eql(pos, item)) {
            return true;
        }
    }
    return false;
}

fn mark_visible_fn(pos: Pos, state: *State) !void {
    if (inside_map(pos, state.tiles) and !contains(state.visible, pos)) {
        try state.visible.append(pos);
    }
}

test "expansive walls" {
    const origin = Pos.new(1, 2);

    const tiles = [_][]const isize{ &.{ 1, 1, 1, 1, 1, 1, 1 }, &.{ 1, 0, 0, 0, 0, 0, 1 }, &.{ 1, 0, 0, 0, 0, 0, 1 }, &.{ 1, 1, 1, 1, 1, 1, 1 } };

    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    var state = State.new(ArrayList(Pos).init(allocator.allocator()), tiles[0..]);

    const ErrorSet = error{ Overflow, OutOfMemory };
    var compute_fov = ComputeFov([]const []const isize, *State, ErrorSet).new(tiles[0..], &state);

    try compute_fov.compute_fov(origin, is_blocking_fn, mark_visible_fn);
    std.debug.print("\nnum visible {}, \n", .{state.visible.items.len});

    const expected = [_][]const isize{ &.{ 1, 1, 1, 1, 1, 1, 1 }, &.{ 1, 1, 1, 1, 1, 1, 1 }, &.{ 1, 1, 1, 1, 1, 1, 1 }, &.{ 1, 1, 1, 1, 1, 1, 1 } };
    try matching_visible(expected[0..], state.visible);
}

test "test_expanding_shadows" {
    const origin = Pos.new(0, 0);

    const tiles = [_][]const isize{ &.{ 0, 0, 0, 0, 0, 0, 0 }, &.{ 0, 1, 0, 0, 0, 0, 0 }, &.{ 0, 0, 0, 0, 0, 0, 0 }, &.{ 0, 0, 0, 0, 0, 0, 0 }, &.{ 0, 0, 0, 0, 0, 0, 0 } };

    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    var state = State.new(ArrayList(Pos).init(allocator.allocator()), tiles[0..]);

    const ErrorSet = error{ Overflow, OutOfMemory };
    var compute_fov = ComputeFov([]const []const isize, *State, ErrorSet).new(tiles[0..], &state);

    try compute_fov.compute_fov(origin, is_blocking_fn, mark_visible_fn);
    std.debug.print("\nnum visible {}, \n", .{state.visible.items.len});

    const expected = [_][]const isize{ &.{ 1, 1, 1, 1, 1, 1, 1 }, &.{ 1, 1, 1, 1, 1, 1, 1 }, &.{ 1, 1, 0, 0, 1, 1, 1 }, &.{ 1, 1, 0, 0, 0, 0, 1 }, &.{ 1, 1, 1, 0, 0, 0, 0 } };
    try matching_visible(expected[0..], state.visible);
}

test "test_no_blind_corners" {
    const origin = Pos.new(3, 0);

    const tiles = [_][]const isize{ &.{ 0, 0, 0, 0, 0, 0, 0 }, &.{ 1, 1, 1, 1, 0, 0, 0 }, &.{ 0, 0, 0, 1, 0, 0, 0 }, &.{ 0, 0, 0, 1, 0, 0, 0 } };

    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    var state = State.new(ArrayList(Pos).init(allocator.allocator()), tiles[0..]);

    const ErrorSet = error{ Overflow, OutOfMemory };
    var compute_fov = ComputeFov([]const []const isize, *State, ErrorSet).new(tiles[0..], &state);

    try compute_fov.compute_fov(origin, is_blocking_fn, mark_visible_fn);
    std.debug.print("\nnum visible {}, \n", .{state.visible.items.len});

    const expected = [_][]const isize{ &.{ 1, 1, 1, 1, 1, 1, 1 }, &.{ 1, 1, 1, 1, 1, 1, 1 }, &.{ 0, 0, 0, 0, 1, 1, 1 }, &.{ 0, 0, 0, 0, 0, 1, 1 } };

    try matching_visible(expected[0..], state.visible);
}
