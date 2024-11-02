const std = @import("std");

const Database = @import("../otimorm.zig").Database;
const Partial = @import("../utils.zig").Partial;

const OrmArgument = @import("lib.zig").OrmArgument;

pub fn Select(comptime Model: type) type {
    const MInfo = @typeInfo(Model);
    comptime var model_type: type = Model;
    comptime var is_array = false;
    if (MInfo == .pointer and MInfo.pointer.size == .Slice) {
        model_type = MInfo.pointer.child;
        is_array = true;
    }

    if (@typeInfo(model_type) != .@"struct") {
        @compileError("M must be a struct");
    }

    if (!@hasDecl(model_type, "Table")) {
        @compileError("M must have Table declaration");
    }

    return struct {
        const Self = @This();

        pub const PossibleError = error{None};
        const ResultSelection = enum {
            First,
            Last,
        };

        arena: std.heap.ArenaAllocator,
        db: *Database,
        orm_argument_where: OrmArgument,
        result_selection: ResultSelection = .First,

        pub fn init(allocator: std.mem.Allocator, db: *Database) Self {
            return Self{
                .arena = std.heap.ArenaAllocator.init(allocator),
                .db = db,
                .orm_argument_where = OrmArgument.init(),
            };
        }

        pub fn deinit(self: *Self) void {
            self.orm_argument_where.deinit();
            self.arena.deinit();
        }

        pub fn where(self: *Self, value: Partial(model_type)) !void {
            const allocator = self.arena.allocator();
            try self.orm_argument_where.parseArguments(allocator, value);
        }

        pub fn send(self: *Self) !?Model {
            const allocator = self.arena.allocator();

            var string_builder = std.ArrayList(u8).init(allocator);
            defer string_builder.deinit();

            var writer = string_builder.writer();

            try writer.writeAll("select ");

            const ModelInfo = @typeInfo(model_type);
            inline for (ModelInfo.@"struct".fields, 1..) |field, i| {
                try writer.writeAll(field.name);

                if (i < ModelInfo.@"struct".fields.len) {
                    try writer.writeAll(",");
                }
            }

            if (is_array) {
                try writer.print(" from {s}", .{model_type.Table});
            } else {
                try writer.print(" from {s}", .{Model.Table});
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

            const query_result = try self.db.exec(output);
            defer query_result.deinit();

            const send_type = if (is_array) std.ArrayList(model_type) else ?model_type;

            //ArrayList is always initialized in the code below, so it will never be null, but otherwise it may be null because
            var result: send_type = if (is_array) undefined else null;
            if (is_array) {
                result = send_type.init(allocator);
            }

            var query_res = try query_result.res.next();
            while (query_res) |row| {
                if (is_array) {
                    try result.append(try row.to(model_type, .{ .map = .name }));
                } else {
                    switch (self.result_selection) {
                        .First => {
                            if (result == null) {
                                result = try row.to(model_type, .{ .map = .name });
                            }
                        },
                        .Last => {
                            result = try row.to(model_type, .{ .map = .name });
                        },
                    }
                }

                query_res = try query_result.res.next();
            }

            if (is_array) {
                return try result.toOwnedSlice();
            }

            return result;
        }
    };
}
