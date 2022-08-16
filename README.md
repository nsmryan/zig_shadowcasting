# Zig Symmetric Shadow Casting

This repository contains a Zig translation of the [Rust translation](https://github.com/nsmryan/shadowcasting) 
of this [Python algorithm](https://www.albertford.com/shadowcasting/).
The best source for information on this algorithm is the Python blog post
by Albert Ford, which is a really beautiful post and worth reading.


The algorithm itself is a very nice field of view algorithm that can be used
in a roguelike for determining visiblity, with the nice properties described
in the original post. I have found this algorithm to give good results, and
I use it with additional laying on top in my [own roguelike](https://github.com/nsmryan/RustRoguelike).


The Zig version is slightly different from the Rust and Python. I tried a series of
different designs before landing on a simplification of the other implementations which
is less generic but easier to use in Zig.


## Example Use

This repository defines a simple Pos (position) type which is just a pair of 'isize's. This can be 
converted to an from user types if you already have a position type in use.


To use this field of view function, simply call 'compute_fov' with the starting location, the generic map structure,
an ArrayList which will be used to mark visible locations, and a function pointer which takes a position and the map,
and returns a boolean indicating whether the given position is blocked on the map.

This keeps the map type and the concept of 'blocking' tiles in the user's control. However, the return type (the visible tiles)
is always an ArrayList(Pos), unlike the Rust and Python where these are generic.

```zig
    // The user must define a function which takes a Pos and the user's map type, and returns
    // whether the given position is blocked in the map.
    fn is_blocking_fn(pos: Pos, tiles: []const []const isize) bool {
        return !inside_map(pos, tiles) or tiles[@intCast(usize, pos.y)][@intCast(usize, pos.x)] == 1;
    }

    // This 'use_fov' function is an example of using 'compute_fov'.
    fn use_fov() void {
        const origin = Pos.new(3, 0);

        // The map, in this case an array of slices, each containing an isize. If the isize is 1, the tile
        // is blocked. If the isize is 0 it is not blocked.
        const tiles = [_][]const isize{ &.{ 0, 0, 0, 0, 0, 0, 0 }, &.{ 1, 1, 1, 1, 0, 0, 0 }, &.{ 0, 0, 0, 1, 0, 0, 0 }, &.{ 0, 0, 0, 1, 0, 0, 0 } };

        // Create the arraylist to store visible tiles.
        var allocator = std.heap.GeneralPurposeAllocator(.{}){};
        var visible = ArrayList(Pos).init(allocator.allocator());
        visible.deinit();

        // Compute FoV using the symmetric shadow casting algorithm.
        try compute_fov(origin, tiles[0..], &visible, is_blocking_fn);
        
        // Now the 'visible' array list contains a series of Pos values indicating which positions were
        // visible.
    }
```

Note that the 'compute_fov' function takes a pointer to an ArrayList instead of creating the ArrayList
itself in order to allow the user to re-use an existing ArrayList, avoiding additional allocations.
