const std = @import("std");

const utils = @import("../utils.zig");

pub const Select = @import("./select.zig").Select;
pub const Insert = @import("./insert.zig").Insert;
pub const Update = @import("./update.zig").Update;
pub const Delete = @import("./delete.zig").Delete;
pub const DeleteAll = @import("./delete_all.zig").DeleteAll;

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
            .arguments = undefined,
            .container = undefined,
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
            return Error.ArgsMustBeStruct;

        inline for (ArgsInfo.@"struct".fields) |field| {
            const value = @field(args, field.name);
            if (!utils.isNull(value)) {
                if (utils.isString(value)) |str| {
                    if (self.arguments) |*arguments| {
                        _ = try arguments.put(field.name, Argument{ .String = str });
                    }
                } else {
                    if (self.arguments) |*arguments| {
                        _ = try arguments.put(field.name, Argument{ .Other = try std.fmt.allocPrint(allocator, "{any}", .{value}) });
                    }
                }
            }
        }
    }
};
