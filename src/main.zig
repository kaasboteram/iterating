const std = @import("std");
const iter = @import("iterating").iter;

pub fn main() !void {
    const arith = struct {
        fn square(x: i32) i32 {
            return x * x;
        }

        fn is_square(x: i32) bool {
            const sqrt = @sqrt(@as(f32, @floatFromInt(x)));
            return sqrt == @floor(sqrt);
        }

        fn try_sqrt(x: i32) ?i32 {
            const sqrt = @sqrt(@as(f32, @floatFromInt(x)));
            return if (sqrt == @floor(sqrt)) @intFromFloat(sqrt) else null;
        }
    };

    const items = try iter(i32).once(-100).chain(iter(i32).rangeInclusive(1, 100).filter(arith.is_square).chain(iter(i32).range(0, 10))).toOwnedSlice(std.heap.page_allocator);
    defer std.heap.page_allocator.free(items);

    std.debug.print("{any}\n", .{items});
}
