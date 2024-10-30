const std = @import("std");

const Database = @import("../otimorm.zig").Database;
const OrmArgument = @import("lib.zig").OrmArgument;

pub fn Insert(comptime M: type) type {
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
        orm_argument: OrmArgument,
        value: M,

        pub fn init(allocator: std.mem.Allocator, db: *Database, value: M) Self {
            return Self{
                .arena = std.heap.ArenaAllocator.init(allocator),
                .db = db,
                .orm_argument = OrmArgument.init(),
                .value = value,
            };
        }

        pub fn deinit(self: *Self) void {
            self.orm_argument.deinit();
            self.arena.deinit();
        }

        pub fn send(self: *Self) !void {
            defer self.deinit();

            const allocator = self.arena.allocator();
            try self.orm_argument.parseArguments(allocator, self.value);

            var string_builder = std.ArrayList(u8).init(allocator);
            defer string_builder.deinit();

            var writer = string_builder.writer();

            try writer.print("insert into {s} (", .{Model.Table});

            if (self.orm_argument.arguments) |arguments| {

                // column names
                {
                    var it = arguments.iterator();
                    var i: u32 = 1;
                    while (it.next()) |arg| : (i += 1) {
                        try writer.print("{s}", .{arg.key_ptr.*});
                        if (i < arguments.count()) {
                            try writer.writeAll(",");
                        }
                    }
                }

                try writer.writeAll(") values (");

                // values
                {
                    var it = arguments.iterator();
                    var i: u32 = 1;
                    while (it.next()) |arg| : (i += 1) {
                        switch (arguments.get(arg.key_ptr.*).?) {
                            .String => |str| {
                                try writer.print("'{s}'", .{str});
                            },
                            .Other => |other| {
                                try writer.print("{s}", .{other});
                            },
                        }
                        if (i < arguments.count()) {
                            try writer.writeAll(",");
                        }
                    }
                }
                try writer.writeAll(");");
            }

            const output = try string_builder.toOwnedSlice();

            (try self.db.exec(output)).deinit();
        }
    };
}
