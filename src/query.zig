const std = @import("std");

const utils = @import("utils.zig");
const Database = @import("otimorm.zig").Database;

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

        allocator: std.mem.Allocator,
        db: *Database,
        orm_argument: OrmArgument,
        value: M,

        pub fn init(allocator: std.mem.Allocator, db: *Database, value: M) Self {
            return Self{
                .allocator = allocator,
                .db = db,
                .orm_argument = OrmArgument.init(),
                .value = value,
            };
        }

        pub fn send(self: *Self) !void {
            try self.orm_argument.parseArguments(self.allocator, self.value);

            var string_builder = std.ArrayList(u8).init(self.allocator);
            defer string_builder.deinit();

            var writer = string_builder.writer();

            try writer.print("insert into {s} (", .{Model.Table});

            if (self.orm_argument.arguments) |arguments| {
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

            if (self.orm_argument.arguments) |arguments| {
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

            const output = try string_builder.toOwnedSlice();
            _ = try self.db.exec(output);
        }
    };
}

pub const OrmArgument = struct {
    const Self = @This();

    pub const Error = error{ArgsMustBeStruct};

    const Argument = union(enum) {
        String: []const u8,
        Other: []const u8,
    };

    arguments: ?std.hash_map.StringHashMap(Argument),
    container: ?std.ArrayList(u8),

    pub fn init() Self {
        return Self{
            .arguments = null,
            .container = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.arguments) |_| {
            self.arguments.?.deinit();
        }
        if (self.container) |_| {
            self.container.?.deinit();
        }
    }

    pub fn parseArguments(self: *Self, allocator: std.mem.Allocator, args: anytype) !void {
        self.arguments = std.hash_map.StringHashMap(Argument).init(allocator);
        self.container = std.ArrayList(u8).init(allocator);

        const ArgsInfo = @typeInfo(@TypeOf(args));
        if (ArgsInfo != .@"struct")
            return Self.Error.ArgsMustBeStruct;

        inline for (ArgsInfo.@"struct".fields) |field| {
            const value = @field(args, field.name);
            if (!utils.isNull(value)) {
                if (utils.isString(value)) |str| {
                    if (self.container) |*container| {
                        const start = container.items.len;

                        var writer = container.writer();
                        try writer.writeAll(str);

                        if (self.arguments) |*arguments| {
                            _ = try arguments.put(field.name, Argument{ .String = container.items[start..] });
                        }
                    }
                } else {
                    if (self.container) |*container| {
                        const start: usize = container.items.len;

                        var writer = container.writer();
                        try writer.print("{any}", .{value});

                        if (self.arguments) |*arguments| {
                            _ = try arguments.put(field.name, Argument{ .Other = container.items[start..] });
                        }
                    }
                }
            }
        }
    }
};
