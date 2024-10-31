const std = @import("std");

const Database = @import("../otimorm.zig").Database;
const OrmArgument = @import("lib.zig").OrmArgument;

pub fn Select(comptime M: type) type {
    const MInfo = @typeInfo(M);
    comptime var model_type: type = M;
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

        pub const Model = model_type;

        pub const PossibleError = error{None};

        arena: std.heap.ArenaAllocator,
        db: *Database,
        orm_argument_where: OrmArgument,

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

        pub fn where(self: *Self, value: model_type) !void {
            const allocator = self.arena.allocator();
            try self.orm_argument_where.parseArguments(allocator, value);
        }

        pub fn send(self: *Self) !?M {
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

            const send_type = if (is_array) std.ArrayList(Model) else ?Model;
            var result: send_type = null;
            if (is_array) {
                result = send_type.init(allocator);
            }

            var query_res = try query_result.res.next();
            while (query_res) |row| {
                if (is_array) {
                    try result.append(try row.to(Model, .{ .map = .name }));
                } else {
                    result = try row.to(Model, .{ .map = .name });
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
