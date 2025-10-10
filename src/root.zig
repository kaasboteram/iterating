const std = @import("std");

pub fn Iter(comptime T: type) type {
    return struct {
        pub fn fromSlice(slice: anytype) Iterator(
            if (@typeInfo(@TypeOf(slice)).pointer.is_const) SliceIterConst(T) else SliceIter(T),
        ) {
            return .{ .inner = .{ .slice = slice } };
        }

        pub fn range(start: T, end: T) Iterator(Range(T)) {
            return .{ .inner = .{ .current = start, .end = end } };
        }

        pub fn rangeInclusive(start: T, end: T) Iterator(RangeInclusive(T)) {
            return .{ .inner = .{ .current = start, .end = end } };
        }

        pub fn once(value: T) Iterator(Once(T)) {
            return .{ .inner = .{ .value = value } };
        }

        pub fn empty() Iterator(Empty(T)) {
            return .{ .inner = .{} };
        }
    };
}

test Iter {
    const testing = @import("std").testing;

    const gpa = testing.allocator;

    const arith = struct {
        fn is_square(x: i32) bool {
            const sqrt = @sqrt(@as(f32, @floatFromInt(x)));
            return sqrt == @floor(sqrt);
        }
    };

    const items = try Iter(i32)
        .once(-100)
        .chain(
            Iter(i32)
                .rangeInclusive(1, 100)
                .filter(arith.is_square)
                .chain(Iter(i32)
                .range(0, 10)),
        )
        .toOwnedSlice(gpa);

    defer gpa.free(items);

    try testing.expectEqualSlices(
        i32,
        &[_]i32{ -100, 1, 4, 9, 16, 25, 36, 49, 64, 81, 100, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
        items,
    );
}

pub fn Iterator(comptime Inner: type) type {
    return struct {
        inner: Inner,

        pub const Item = Inner.Item;

        const _Inner = Inner;

        const Self = @This();

        pub fn next(self: *Self) ?Item {
            return self.inner.next();
        }

        pub fn map(
            self: Self,
            comptime T: type,
            f: fn (Item) T,
        ) Iterator(adapters.Map(Inner, T, f)) {
            return .{ .inner = .{ .inner = self.inner } };
        }

        pub fn filter(self: Self, predicate: fn (Item) bool) Iterator(adapters.Filter(
            Inner,
            predicate,
        )) {
            return .{ .inner = .{ .inner = self.inner } };
        }

        pub fn filterMap(
            self: Self,
            comptime T: type,
            f: anytype,
        ) Iterator(adapters.FilterMap(Inner, T, f)) {
            return .{ .inner = .{ .inner = self.inner } };
        }

        pub fn take(
            self: Self,
            n: usize,
        ) Iterator(adapters.Take(Inner)) {
            return .{ .inner = .{ .inner = self.inner, .n = n } };
        }

        pub fn enumerate(self: Self) Iterator(adapters.Enumerate(Inner)) {
            return .{ .inner = .{ .inner = self.inner } };
        }

        pub fn fold(self: Self, comptime T: type, init: T, f: anytype) T {
            var mutSelf = self;
            var acc = init;
            while (mutSelf.next()) |x| {
                acc = f(acc, x);
            }
            return acc;
        }

        pub fn any(self: Self, f: fn (Item) bool) bool {
            var mutSelf = self;
            while (mutSelf.next()) |v| {
                if (f(v)) return true;
            }

            return false;
        }

        pub fn all(self: Self, f: fn (Item) bool) bool {
            var mutSelf = self;
            while (mutSelf.next()) |v| {
                if (!f(v)) return false;
            }

            return true;
        }

        pub fn count(self: Self) usize {
            return self.fold(usize, 0, struct {
                fn inc(i: usize, _: Item) usize {
                    return i + 1;
                }
            }.inc);
        }

        pub fn last(self: Self) ?Item {
            return self.fold(?Item, null, struct {
                inline fn some(_: ?Item, x: Item) ?Item {
                    return x;
                }
            }.some);
        }

        pub fn chain(self: Self, other: anytype) Iterator(adapters.Chain(Inner, @TypeOf(other)._Inner)) {
            return .{ .inner = .{ .first = self.inner, .second = other.inner } };
        }

        pub fn zip(self: Self, other: anytype) Iterator(adapters.Zip(Inner, @TypeOf(other)._Inner)) {
            return .{ .inner = .{ .a = self.inner, .b = other.inner } };
        }

        pub fn toOwnedSlice(self: Self, gpa: std.mem.Allocator) ![]const Item {
            var list: std.ArrayList(Item) = .empty;
            errdefer list.deinit(gpa);

            try self.collectInto(&list, gpa);

            return try list.toOwnedSlice(gpa);
        }

        pub fn collectInto(self: Self, list: *std.ArrayList(Item), gpa: std.mem.Allocator) !void {
            var mutSelf = self;
            while (mutSelf.next()) |val| {
                try list.append(gpa, val);
            }
        }
    };
}

pub const adapters = struct {
    pub fn Map(
        comptime Inner: type,
        comptime T: type,
        comptime f: fn (Inner.Item) T,
    ) type {
        return struct {
            inner: Inner,

            pub const Item = T;

            const Self = @This();

            pub fn next(self: *Self) ?Item {
                return if (self.inner.next()) |val| f(val) else null;
            }
        };
    }

    pub fn Filter(comptime Inner: type, comptime predicate: fn (Inner.Item) bool) type {
        return struct {
            inner: Inner,

            pub const Item = Inner.Item;

            const Self = @This();

            pub fn next(self: *Self) ?Item {
                while (self.inner.next()) |val| {
                    if (predicate(val)) return val;
                }

                return null;
            }
        };
    }

    pub fn FilterMap(comptime Inner: type, comptime T: type, comptime f: fn (Inner.Item) ?T) type {
        return struct {
            inner: Inner,

            pub const Item = T;

            const Self = @This();

            pub fn next(self: *Self) ?Item {
                while (self.inner.next()) |val| {
                    if (f(val)) |mapped| return mapped;
                }

                return null;
            }
        };
    }

    pub fn Take(comptime Inner: type) type {
        return struct {
            i: usize = 0,
            n: usize,
            inner: Inner,

            pub const Item = Inner.Item;

            const Self = @This();

            pub fn next(self: *Self) ?Item {
                if (self.i >= self.n) return null;
                defer self.i += 1;
                return self.inner.next();
            }
        };
    }

    pub fn Enumerate(comptime Inner: type) type {
        return struct {
            inner: Inner,
            i: usize = 0,

            pub const Item = struct { usize, Inner.Item };

            const Self = @This();

            pub fn next(self: *Self) ?Item {
                if (self.inner.next()) |val| {
                    defer self.i += 1;
                    return .{ self.i, val };
                }

                return null;
            }
        };
    }

    pub fn Chain(comptime First: type, comptime Second: type) type {
        comptime std.debug.assert(First.Item == Second.Item);
        return struct {
            first: First,
            second: Second,

            pub const Item = First.Item;

            const Self = @This();

            pub fn next(self: *Self) ?Item {
                return if (self.first.next()) |x| x else self.second.next();
            }
        };
    }

    pub fn Zip(comptime A: type, comptime B: type) type {
        return struct {
            a: A,
            b: B,

            pub const Item = struct { A.Item, B.Item };

            const Self = @This();

            pub fn next(self: *Self) ?Item {
                const x = self.a.next() orelse return null;
                const y = self.b.next() orelse return null;
                return .{ x, y };
            }
        };
    }

    test Zip {
        const testing = @import("std").testing;

        var it = Iter(i32).once(10).zip(Iter(i32).once(20));

        try testing.expectEqualDeep(struct { i32, i32 }{ 10, 20 }, it.next().?);
    }
};

pub fn Range(comptime T: type) type {
    return struct {
        current: T,
        end: T,

        pub const Item = T;

        const Self = @This();

        pub fn next(self: *Self) ?Item {
            if (self.current >= self.end) return null;
            defer self.current += 1;
            return self.current;
        }
    };
}

pub fn RangeInclusive(comptime T: type) type {
    return struct {
        current: T,
        end: T,

        pub const Item = T;

        const Self = @This();

        pub fn next(self: *Self) ?Item {
            if (self.current > self.end) return null;
            defer self.current += 1;
            return self.current;
        }
    };
}

pub fn Once(comptime T: type) type {
    return struct {
        value: ?T,

        pub const Item = T;

        const Self = @This();

        pub fn next(self: *Self) ?Item {
            defer self.value = null;
            return self.value;
        }
    };
}

pub fn SliceIter(comptime T: type) type {
    return struct {
        slice: []T,
        index: usize = 0,

        pub const Item = *T;

        const Self = @This();

        pub fn next(self: *Self) ?Item {
            if (self.index >= self.slice.len) return null;
            defer self.index += 1;
            return &self.slice[self.index];
        }
    };
}

pub fn SliceIterConst(comptime T: type) type {
    return struct {
        slice: []const T,
        index: usize = 0,

        pub const Item = *const T;

        const Self = @This();

        pub fn next(self: *Self) ?Item {
            if (self.index >= self.slice.len) return null;
            defer self.index += 1;
            return &self.slice[self.index];
        }
    };
}

pub fn Empty(comptime T: type) type {
    return struct {
        pub const Item = T;

        pub fn next(_: Empty(T)) ?Item {
            return null;
        }
    };
}

test Empty {
    const testing = @import("std").testing;

    var it = Iter(i32).empty();

    try testing.expectEqual(null, it.next());
}
