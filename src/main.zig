const std = @import("std");
const testing = std.testing;

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
pub fn ComputeFov(comptime Map: type, comptime Result: type) type {
    return struct {
        const Self = @This();

        map: Map,
        result: Result,

        pub const MarkVisible = fn (pos: Pos, map: Map) void;

        pub const IsBlocking = fn (pos: Pos, result: Result) void;

        pub fn new(map: Map, result: Result) Self {
            return Self{ .map = map, .result = result };
        }

        pub fn compute_fov(self: *Self, origin: Pos, is_blocking: IsBlocking, mark_visible: MarkVisible) void {
            mark_visible(origin, self.map);

            var index = 0;
            while (index < 4) : (index += 1) {
                const quadrant = Quadrant.new(Cardinal.from_index(index), origin);

                //const first_row = Row.new(1, Rational::new(-1, 1), Rational::new(1, 1));
                const first_row = Row.new(1, Rational.new(-1, 1), Rational.new(1, 1));

                scan(first_row, quadrant, is_blocking, mark_visible);
            }
        }

        fn scan(self: *Self, input_row: Row, quadrant: Quadrant, is_blocking: IsBlocking, mark_visible: MarkVisible) void {
            var prev_tile = null;

            var row = input_row;

            var iter = row.tiles();
            for (iter.next()) |tile| {
                const tile_is_wall = is_blocking(quadrant.transform(tile));
                const tile_is_floor = !tile_is_wall;

                var prev_is_wall = false;
                if (prev_tile) |prev| {
                    prev_is_wall = is_blocking(quadrant.transform(prev));
                }

                var prev_is_floor = false;
                if (prev_tile) |prev| {
                    prev_is_floor = !is_blocking(quadrant.transform(prev));
                }

                if (tile_is_wall or is_symmetric(row, tile)) {
                    const pos = quadrant.transform(tile);

                    mark_visible(pos);
                }

                if (prev_is_wall and tile_is_floor) {
                    row.start_slope = slope(tile);
                }

                if (prev_is_floor and tile_is_wall) {
                    const next_row = row.next();

                    next_row.end_slope = slope(tile);

                    scan(next_row, quadrant, is_blocking, mark_visible);
                }

                prev_tile = tile;
            }

            if (prev_tile) |tile| {
                if (!is_blocking(quadrant.transform(tile))) {
                    self.scan(row.next(), quadrant, is_blocking, mark_visible);
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

    fn transform(self: *Quadrant, tile: Pos) Pos {
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
        return Row{ depth, start_slope, end_slope };
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

    fn next(self: *Row) Row {
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

fn is_symmetric(row: Row, tile: Pos) bool {
    const col = tile.y;

    const depth_times_start = Rational.new(row.depth, 1).mult(row.start_slope);
    const depth_times_end = Rational.new(row.depth, 1).mult(row.end_slope);

    const col_rat = Rational.new(col, 1);

    const symmetric = col_rat >= depth_times_start and col_rat <= depth_times_end;

    return symmetric;
}

fn round_ties_up(n: Rational) isize {
    return (n + Rational.new(1, 2)).floor();
}

fn round_ties_down(n: Rational) isize {
    return (n - Rational.new(1, 2)).ceil();
}

const Rational = struct {
    num: isize,
    denom: isize,

    pub fn new(num: isize, denom: isize) Rational {
        return Rational{ .num = num, .denom = denom };
    }

    pub fn mult(self: Rational, other: Rational) Rational {
        return Rational.new(self.num * other.num, self.denom * other.denom);
    }

    pub fn add(self: Rational, other: Rational) Rational {
        return Rational.new(self.num * other.denom + other.num * self.denom, self.denom * other.denom);
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

fn inside_map(pos: Pos, map: [][]Pos) bool {
    const is_inside = @as(usize, pos.y) < map.len and @as(usize, pos.x) < map[0].len;
    return is_inside;
}

fn contains(slice: []Pos, pos: Pos) bool {
    var index = 0;
    while (index < slice.len) {
        if (std.meta.eql(slice[index], pos)) {
            return true;
        }
    }
    return false;
}

fn matching_visible(expected: [][]usize, visible: []Pos) void {
    var y = 0;
    while (y < expected.len) {
        var x = 0;
        while (x < expected[0].len) {
            if (contains(visible, Pos.new(@as(isize, x), @as(isize, y)))) {
                std.debug.print("1\n");
            } else {
                std.debug.print("0\n");
            }
            std.debug.assert(expected[y][x] == 1, contains(visible, Pos.new(@as(isize, x), @as(isize, y))));
        }
        std.debug.print("\n");
    }
}

fn is_blocking(pos: Pos, tiles: [][]Pos) bool {
    return !inside_map(pos, tiles) or tiles[pos.1 as usize][pos.0 as usize] == 1;
}

// TODO this needs a struct containing the tiles map and an arraylist of visible tiles.
// this will then be the second argument to mark_visible to make this data available.
fn mark_visible(pos: Pos, visible: [][]bool) void {
    if (inside_map(pos, tiles) && !visible.contains(&pos)) {
        visible.push(pos);
    }
}

test "expansive walls" {
    const origin = Pos.new(1, 2);

    const tiles = [_][_]isize{[_]isize{1, 1, 1, 1, 1, 1, 1},
                     [_]isize{1, 0, 0, 0, 0, 0, 1},
                     [_]isize{1, 0, 0, 0, 0, 0, 1},
                     [_]isize{1, 1, 1, 1, 1, 1, 1}};

    var visible = Vec::new();
    var mark_visible = |pos: Pos| {
        if inside_map(pos, &tiles) && !visible.contains(&pos) {
            visible.push(pos);
        }
    };

    compute_fov(origin, &mut is_blocking, &mut mark_visible);

    const expected = [_][_]isize{[_]isize{1, 1, 1, 1, 1, 1, 1},
                        [_]isize{1, 1, 1, 1, 1, 1, 1},
                        [_]isize{1, 1, 1, 1, 1, 1, 1},
                        [_]isize{1, 1, 1, 1, 1, 1, 1}};
    matching_visible(expected, visible);
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
//            visible.push(pos);
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
//            visible.push(pos);
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
