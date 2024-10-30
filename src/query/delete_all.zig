const std = @import("std");

const Database = @import("../otimorm.zig").Database;

pub fn DeleteAll(comptime M: type) type {
    if (@typeInfo(M) != .@"struct") {
        @compileError("M must be a struct");
    }

    if (!@hasDecl(M, "Table")) {
        @compileError("M must have Table declaration");
    }

    return struct {
        const Self = @This();

        pub const Model = M;
        pub const PossibleError = error{None};

        arena: std.heap.ArenaAllocator,
        db: *Database,

        pub fn init(allocator: std.mem.Allocator, db: *Database) Self {
            return Self{
                .arena = std.heap.ArenaAllocator.init(allocator),
                .db = db,
            };
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }

        pub fn send(self: *Self) !void {
            defer self.deinit();

            const allocator = self.arena.allocator();

            var string_builder = std.ArrayList(u8).init(allocator);
            defer string_builder.deinit();

            var writer = string_builder.writer();

            try writer.print("delete from {s};", .{Model.Table});

            const output = try string_builder.toOwnedSlice();

            (try self.db.exec(output)).deinit();
        }
    };
}
