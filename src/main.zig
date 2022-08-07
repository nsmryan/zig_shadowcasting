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
//pub fn ComputeFov(comptime Map: type, comptime Result: type) {
//    return struct {
//        const Self = @This;
//
//        map: Map,
//        result: Result,
//
//        pub const MarkVisible = fn (pos: Pos, map: Map) void;
//
//        pub const IsBlocking = fn (pos: Pos, result: Result) void;
//
//        pub fn init(map: Map, result: Result) Self {
//            return Self { .map = map, .result = result };
//        }
//
//        pub fn compute_fov(origin: Pos, is_blocking: IsBlocking, mark_visible: MarkVisible) void {
//            mark_visible(origin, self.map);
//
//            var index = 0;
//            while (index < 4) |index += 1| {
//                let quadrant = Quadrant.init(Cardinal.from_index(i), origin);
//
//                //const first_row = Row.init(1, Rational::new(-1, 1), Rational::new(1, 1));
//                const first_row = Row.init(1, -1, 1);
//
//                scan(first_row, quadrant, is_blocking, mark_visible);
//            }
//        }
//
//        fn scan(row: Row, quadrant: Quadrant, is_blocking: IsBlocking, mark_visible: MarkVisible) void {
//            var prev_tile = None;
//
//            var row = row;
//
//            for tile in row.tiles() {
//                let tile_is_wall = is_blocking(quadrant.transform(tile));
//                let tile_is_floor = !tile_is_wall;
//
//                let prev_is_wall = prev_tile.map_or(false, |prev| is_blocking(quadrant.transform(prev)));
//                let prev_is_floor = prev_tile.map_or(false, |prev| !is_blocking(quadrant.transform(prev)));
//
//                if tile_is_wall || is_symmetric(row, tile) {
//                    let pos = quadrant.transform(tile);
//
//                    mark_visible(pos);
//                }
//
//                if prev_is_wall && tile_is_floor {
//                    row.start_slope = slope(tile);
//                }
//
//                if prev_is_floor && tile_is_wall {
//                    let mut next_row = row.next();
//
//                    next_row.end_slope = slope(tile);
//
//                    scan(next_row, quadrant, is_blocking, mark_visible);
//                }
//
//                prev_tile = Some(tile);
//            }
//
//            if prev_tile.map_or(false, |tile| !is_blocking(quadrant.transform(tile))) {
//                scan(row.next(), quadrant, is_blocking, mark_visible);
//            }
//        }
//
//    };
//}

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

//const Row = struct {
//    depth: isize,
//    start_slope: Rational,
//    end_slope: Rational,
//
//    fn new(depth: isize, start_slope: Rational, end_slope: Rational) Row {
//        return Row { depth, start_slope, end_slope };
//    }
//
//    // NOTE the Rust version uses an interator. For Zig, I will likely define a separate
//    // type for this, or look at idiomatic iterators.
//    fn tiles(self: *Row) impl Iterator<Item=Pos> {
//        const depth_times_start = Rational::new(self.depth, 1) * self.start_slope;
//        const depth_times_end = Rational::new(self.depth, 1) * self.end_slope;
//
//        const min_col = round_ties_up(depth_times_start);
//
//        const max_col = round_ties_down(depth_times_end);
//
//        const depth = self.depth;
//
//        return (min_col..=max_col).map(move |col| (depth, col));
//    }
//
//    fn next(self: *Row) Row {
//        return Row.init(self.depth + 1, self.start_slope, self.end_slope);
//    }
//}

fn slope(tile: Pos) Rational {
    const row_depth = tile.x;
    const col = tile.y;
    return Rational.init(2 * col - 1, 2 * row_depth);
}

fn is_symmetric(row: Row, tile: Pos) bool {
    const col = tile.y;

    const depth_times_start = Rational.new(row.depth, 1) * row.start_slope;
    const depth_times_end = Rational.new(row.depth, 1) * row.end_slope;

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

    pub fn mult(self: Rational, other: Rational) Rational {}

    pub fn add(self: Rational, other: Rational) Rational {}

    pub fn ceil(self: Rational) isize {
        const div = self.num / self.denom;
        return div + @boolToInt(self.num % self.denom > 0);
    }

    pub fn floor(self: Rational) isize {
        return self.num / self.denom;
    }
};

//#[cfg(test)]
//fn inside_map<T>(pos: Pos, map: &Vec<Vec<T>>) bool {
//    let is_inside = (pos.1 as usize) < map.len() && (pos.0 as usize) < map[0].len();
//    return is_inside;
//}
//
//#[cfg(test)]
//fn matching_visible(expected: Vec<Vec<usize>>, visible: Vec<(isize, isize)>) {
//    for y in 0..expected.len() {
//        for x in 0..expected[0].len() {
//            if visible.contains(&(x as isize, y as isize)) {
//                print!("1");
//            } else {
//                print!("0");
//            }
//            assert_eq!(expected[y][x] == 1, visible.contains(&(x as isize, y as isize)));
//        }
//        println!();
//    }
//}
//
//#[test]
//fn test_expansive_walls() {
//    let origin = (1, 2);
//
//    let tiles = vec!(vec!(1, 1, 1, 1, 1, 1, 1),
//                     vec!(1, 0, 0, 0, 0, 0, 1),
//                     vec!(1, 0, 0, 0, 0, 0, 1),
//                     vec!(1, 1, 1, 1, 1, 1, 1));
//
//    let mut is_blocking = |pos: Pos| {
//        return  !inside_map(pos, &tiles) || tiles[pos.1 as usize][pos.0 as usize] == 1;
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
//                        vec!(1, 1, 1, 1, 1, 1, 1),
//                        vec!(1, 1, 1, 1, 1, 1, 1));
//    matching_visible(expected, visible);
//}
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
