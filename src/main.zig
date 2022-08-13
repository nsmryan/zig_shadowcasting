const std = @import("std");
const testing = std.testing;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

/// This Pos type is expected to be generate enough to allow the user
/// to cast into and out of their own type, such as from the euclid crate.
pub const Pos = struct {
    x: isize,
    y: isize,

    pub fn new(x: isize, y: isize) Pos {
        return Pos{ .x = x, .y = y };
    }
};

/// Compute FOV information for a given position using the shadow mapping algorithm.
///
/// This uses the is_blocking closure, which checks whether a given position is
/// blocked (such as by a wall), and is expected to capture some kind of grid
/// or map from the user.
///
/// The mark_visible closure provides the ability to collect visible tiles. This
/// may push them to a vector (captured in the closure's environment), or
/// modify a cloned version of the map.
///
///
/// I tried to write a nicer API which would modify the map as a separate user
/// data, but I can't work out the lifetime annotations.
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
            while (iter.next()) |tile| {
                const tile_is_wall = is_blocking(quadrant.transform(tile), self.map);
                const tile_is_floor = !tile_is_wall;

                var prev_is_wall = false;
                if (prev_tile) |prev| {
                    prev_is_wall = is_blocking(quadrant.transform(prev), self.map);
                }

                var prev_is_floor = false;
                if (prev_tile) |prev| {
                    prev_is_floor = !is_blocking(quadrant.transform(prev), self.map);
                }

                if (tile_is_wall or try is_symmetric(row, tile)) {
                    const pos = quadrant.transform(tile);

                    try mark_visible(pos, self.result);
                }

                if (prev_is_wall and tile_is_floor) {
                    row.start_slope = slope(tile);
                }

                if (prev_is_floor and tile_is_wall) {
                    if (row.next()) |next_row| {
                        var next_row_var = next_row;
                        next_row_var.end_slope = slope(tile);

                        try self.scan(next_row_var, quadrant, is_blocking, mark_visible);
                    }
                }

                prev_tile = tile;
            }

            if (prev_tile) |tile| {
                if (!is_blocking(quadrant.transform(tile), self.map)) {
                    if (row.next()) |next_row| {
                        try self.scan(next_row, quadrant, is_blocking, mark_visible);
                    }
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

    //    // NOTE the Rust version uses an interator. For Zig, I will likely define a separate
    //    // type for this, or look at idiomatic iterators.
    fn tiles(self: *Row) RowIter {
        const depth_times_start = Rational.new(self.depth, 1).mult(self.start_slope);
        const depth_times_end = Rational.new(self.depth, 1).mult(self.end_slope);

        const min_col = round_ties_up(depth_times_start);

        const max_col = round_ties_down(depth_times_end);

        const depth = self.depth;

        //return (min_col..=max_col).map(move |col| (depth, col));
        return RowIter.new(min_col, max_col, depth);
    }

    fn next(self: *Row) ?Row {
        return Row.new(self.depth + 1, self.start_slope, self.end_slope);
    }
};

const RowIter = struct {
    min_col: isize,
    max_col: isize,
    depth: isize,
    col: isize = 0,

    pub fn new(min_col: isize, max_col: isize, depth: isize) RowIter {
        return RowIter{ .min_col = min_col, .max_col = max_col, .depth = depth };
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

    pub fn new(num: isize, denom: isize) Rational {
        return Rational{ .num = num, .denom = denom };
    }

    pub fn gteq(self: Rational, other: Rational) Rational.Error!bool {
        return (try std.math.absInt(self.num * self.denom)) >= (try std.math.absInt(other.num * other.denom));
    }

    pub fn lteq(self: Rational, other: Rational) Rational.Error!bool {
        return (try std.math.absInt(self.num * self.denom)) <= (try std.math.absInt(other.num * other.denom));
    }

    pub fn mult(self: Rational, other: Rational) Rational {
        return Rational.new(self.num * other.num, self.denom * other.denom);
    }

    pub fn add(self: Rational, other: Rational) Rational {
        return Rational.new(self.num * other.denom + other.num * self.denom, self.denom * other.denom);
    }

    pub fn sub(self: Rational, other: Rational) Rational {
        return Rational.new(self.num * other.denom - other.num * self.denom, self.denom * other.denom);
    }

    pub fn ceil(self: Rational) isize {
        if (self.denom != 0) {
            const div = @divFloor(self.num, self.denom);
            return div + @boolToInt(@mod(self.num, self.denom) > 0);
        } else {
            // Idk whether this can happen for this algorithm.
            return 0;
        }
    }

    pub fn floor(self: Rational) isize {
        if (self.denom != 0) {
            return @divFloor(self.num, self.denom);
        } else {
            // Idk whether this can happen for this algorithm.
            return 0;
        }
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
    try std.testing.expectEqual(Rational.new(1, 4), Rational.new(1, 2).mult(Rational.new(1, 2)));
    try std.testing.expectEqual(Rational.new(4, 9), Rational.new(2, 3).mult(Rational.new(2, 3)));
}

fn inside_map(pos: Pos, map: []const []const isize) bool {
    const is_inside = @bitCast(usize, pos.y) < map.len and @bitCast(usize, pos.x) < map[0].len;
    return is_inside;
}

//fn contains(slice: []Pos, pos: Pos) bool {
//    var index = 0;
//    while (index < slice.len) {
//        if (std.meta.eql(slice[index], pos)) {
//            return true;
//        }
//    }
//    return false;
//}

fn matching_visible(expected: []const []const isize, visible: ArrayList(Pos)) void {
    var y: usize = 0;
    while (y < expected.len) {
        var x: usize = 0;
        while (x < expected[0].len) {
            if (contains(visible, Pos.new(@intCast(isize, x), @intCast(isize, y)))) {
                std.debug.print("1\n", .{});
            } else {
                std.debug.print("0\n", .{});
            }
            std.debug.assert(expected[y][x] == 1 and contains(visible, Pos.new(@bitCast(isize, x), @bitCast(isize, y))));
        }
        std.debug.print("\n", .{});
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

    //const tiles = [_][]const isize{ &.{ 1, 1, 1, 1, 1, 1, 1 }, };
    const tiles = [_][]const isize{ &.{ 1, 1, 1, 1, 1, 1, 1 }, &.{ 1, 0, 0, 0, 0, 0, 1 }, &.{ 1, 0, 0, 0, 0, 0, 1 }, &.{ 1, 1, 1, 1, 1, 1, 1 } };

    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    var visible = ArrayList(Pos).init(allocator.allocator());

    var state = State.new(visible, tiles[0..]);

    const ErrorSet = error{ Overflow, OutOfMemory };
    var compute_fov = ComputeFov([]const []const isize, *State, ErrorSet).new(tiles[0..], &state);

    try compute_fov.compute_fov(origin, is_blocking_fn, mark_visible_fn);

    const expected = [_][]const isize{ &.{ 1, 1, 1, 1, 1, 1, 1 }, &.{ 1, 1, 1, 1, 1, 1, 1 }, &.{ 1, 1, 1, 1, 1, 1, 1 }, &.{ 1, 1, 1, 1, 1, 1, 1 } };
    matching_visible(expected[0..], visible);
}

//
//
//#[test]
//fn test_expanding_shadows() {
//    let origin = (0, 0);
//
//    let tiles = vec!(vec!(0, 0, 0, 0, 0, 0, 0),
//                     vec!(0, 1, 0, 0, 0, 0, 0),
//                     vec!(0, 0, 0, 0, 0, 0, 0),
//                     vec!(0, 0, 0, 0, 0, 0, 0),
//                     vec!(0, 0, 0, 0, 0, 0, 0));
//
//    let mut is_blocking = |pos: Pos| {
//        return !inside_map(pos, &tiles) || tiles[pos.1 as usize][pos.0 as usize] == 1;
//    };
//
//    let mut visible = Vec::new();
//    let mut mark_visible = |pos: Pos| {
//        if inside_map(pos, &tiles) && !visible.contains(&pos) {
//            visible.append(pos);
//        }
//    };
//
//    compute_fov(origin, &mut is_blocking, &mut mark_visible);
//
//    let expected = vec!(vec!(1, 1, 1, 1, 1, 1, 1),
//                        vec!(1, 1, 1, 1, 1, 1, 1),
//                        vec!(1, 1, 0, 0, 1, 1, 1),
//                        vec!(1, 1, 0, 0, 0, 0, 1),
//                        vec!(1, 1, 1, 0, 0, 0, 0));
//    matching_visible(expected, visible);
//}
//
//#[test]
//fn test_no_blind_corners() {
//    let origin = (3, 0);
//
//    let tiles = vec!(vec!(0, 0, 0, 0, 0, 0, 0),
//                     vec!(1, 1, 1, 1, 0, 0, 0),
//                     vec!(0, 0, 0, 1, 0, 0, 0),
//                     vec!(0, 0, 0, 1, 0, 0, 0));
//
//    let mut is_blocking = |pos: Pos| {
//        let outside = (pos.1 as usize) >= tiles.len() || (pos.0 as usize) >= tiles[0].len();
//        return  outside || tiles[pos.1 as usize][pos.0 as usize] == 1;
//    };
//
//    let mut visible = Vec::new();
//    let mut mark_visible = |pos: Pos| {
//        let outside = (pos.1 as usize) >= tiles.len() || (pos.0 as usize) >= tiles[0].len();
//
//        if !outside && !visible.contains(&pos) {
//            visible.append(pos);
//        }
//    };
//
//    compute_fov(origin, &mut is_blocking, &mut mark_visible);
//
//    let expected = vec!(vec!(1, 1, 1, 1, 1, 1, 1),
//                        vec!(1, 1, 1, 1, 1, 1, 1),
//                        vec!(0, 0, 0, 0, 1, 1, 1),
//                        vec!(0, 0, 0, 0, 0, 1, 1));
//    matching_visible(expected, visible);
//}
