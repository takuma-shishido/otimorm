const std = @import("std");

const Database = @import("../otimorm.zig").Database;
const Partial = @import("../utils.zig").Partial;

const OrmArgument = @import("lib.zig").OrmArgument;

pub fn Update(comptime Model: type) type {
    if (@typeInfo(Model) != .@"struct") {
        @compileError("M must be a struct");
    }

    if (!@hasDecl(Model, "Table")) {
        @compileError("M must have Table declaration");
    }

    return struct {
        const Self = @This();

        pub const PossibleError = error{None};

        arena: std.heap.ArenaAllocator,
        db: *Database,
        orm_argument: OrmArgument,
        orm_argument_where: OrmArgument,
        value: Partial(Model),

        pub fn init(allocator: std.mem.Allocator, db: *Database, value: Partial(Model)) Self {
            return Self{
                .arena = std.heap.ArenaAllocator.init(allocator),
                .db = db,
                .orm_argument = OrmArgument.init(),
                .orm_argument_where = OrmArgument.init(),
                .value = value,
            };
        }

        pub fn deinit(self: *Self) void {
            self.orm_argument.deinit();
            self.orm_argument_where.deinit();
            self.arena.deinit();
        }

        pub fn where(self: *Self, value: Partial(Model)) !void {
            const allocator = self.arena.allocator();
            try self.orm_argument_where.parseArguments(allocator, value);
        }

        pub fn send(self: *Self) !void {
            defer self.deinit();

            const allocator = self.arena.allocator();
            try self.orm_argument.parseArguments(allocator, self.value);

            var string_builder = std.ArrayList(u8).init(allocator);
            defer string_builder.deinit();

            var writer = string_builder.writer();

            try writer.print("update {s} set ", .{Model.Table});

            if (self.orm_argument.arguments) |arguments| {
                if (arguments.count() > 1) {
                    try writer.writeAll("(");
                }

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

                if (arguments.count() > 1) {
                    try writer.writeAll(") = (");
                } else {
                    try writer.writeAll(" = ");
                }

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

                if (arguments.count() > 1) {
                    try writer.writeAll(")");
                }
            }

            if (self.orm_argument_where.arguments) |arguments| {
                try writer.writeAll(" where ");

                var it = arguments.iterator();
                var i: u32 = 1;
                while (it.next()) |arg| : (i += 1) {
                    try writer.print("{s}=", .{arg.key_ptr.*});

                    switch (arguments.get(arg.key_ptr.*).?) {
                        .String => |str| {
                            try writer.print("'{s}'", .{str});
                        },
                        .Other => |value| {
                            try writer.print("{s}", .{value});
                        },
                    }

                    if (i < arguments.count()) {
                        try writer.writeAll(" and ");
                    }
                }
            }

            try writer.writeAll(";");

            const output = try string_builder.toOwnedSlice();

            (try self.db.exec(output)).deinit();
        }
    };
}
