const std = @import("std");

const pg = @import("pg");
const utils = @import("utils.zig");
const Query = @import("query/lib.zig");

pub const Database = struct {
    const Self = @This();

    pub const Error = error{ AlreadyInit, ExecFailure, NotConnected };

    pub const Result = struct {
        res: *pg.Result,

        pub fn deinit(self: Result) void {
            self.res.deinit();
        }

        pub fn numberOfColumns(self: Result) usize {
            return self.res.number_of_columns;
        }

        pub fn columnName(self: Result, column_number: usize) ?[]const u8 {
            if (column_number > self.res.column_names.len) return null;

            return self.res.column_names[column_number];
        }

        pub fn getValue(_: Result, row: pg.Row, column_number: usize) ?[]const u8 {
            return row.get([]const u8, column_number);
        }
    };

    allocator: std.mem.Allocator,
    connected: bool,
    _pool: *pg.Pool,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .connected = false,
            ._pool = undefined,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.connected) {
            self._pool.deinit();
        }
    }

    pub fn exec(self: Self, query: []const u8) !Result {
        if (!self.connected)
            return Error.NotConnected;

        const result = try self._pool.queryOpts(query, .{}, .{ .column_names = true });

        return Result{ .res = result };
    }

    pub fn connect(self: *Self, uri: []const u8) !void {
        if (self.connected)
            return Error.AlreadyInit;

        const conn_info = try std.Uri.parse(uri);
        const pool = try pg.Pool.initUri(self.allocator, conn_info, 10, 10_000);

        self._pool = pool;
        self.connected = true;
    }

    pub fn select(self: *Self, comptime T: type) Query.Select(T) {
        return Query.Select(T).init(self.allocator, self);
    }

    pub fn insert(self: *Self, comptime T: type, value: T) Query.Insert(T) {
        return Query.Insert(T).init(self.allocator, self, value);
    }

    pub fn update(self: *Self, comptime T: type, value: T) Query.Update(T) {
        return Query.Update(T).init(self.allocator, self, value);
    }

    pub fn delete(self: *Self, comptime T: type, value: T) Query.Delete(T) {
        return Query.Delete(T).init(self.allocator, self, value);
    }

    pub fn deleteAll(self: *Self, comptime T: type) Query.DeleteAll(T) {
        return Query.DeleteAll(T).init(self.allocator, self);
    }
};

test "Database: Insert" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    try db.connect("postgresql://postgres:postgres@localhost:5432/orm");

    const User = struct {
        pub const Table = "test_table";

        test_value: []const u8,
        test_num: ?i32,
        test_bool: bool,
    };

    {
        var insert = db.insert(User, .{ .test_value = "foo", .test_num = undefined, .test_bool = true });
        try insert.send();
    }
}

test "Database: Select" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    try db.connect("postgresql://postgres:postgres@localhost:5432/orm");

    const User = struct {
        pub const Table = "test_table";

        test_value: []const u8,
        test_num: ?i32,
        test_bool: bool,
    };

    {
        var select = db.select([]User);
        try select.where(.{ .test_value = "foo", .test_num = undefined, .test_bool = true });
        defer select.deinit();

        if (try select.send()) |models| {
            for (models) |model| {
                _ = model; // autofix
            }
        }
    }
}

test "Database: Update" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    try db.connect("postgresql://postgres:postgres@localhost:5432/orm");

    const User = struct {
        pub const Table = "test_table";

        test_value: []const u8,
        test_num: ?i32,
        test_bool: bool,
    };

    {
        var update = db.update(User, .{ .test_value = "fooha", .test_num = undefined, .test_bool = false });
        try update.where(.{ .test_value = "foo", .test_num = undefined, .test_bool = true });
        try update.send();
    }
}

test "Database: Delete" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    try db.connect("postgresql://postgres:postgres@localhost:5432/orm");

    const User = struct {
        pub const Table = "test_table";

        test_value: []const u8,
        test_num: ?i32,
        test_bool: bool,
    };

    {
        var delete = db.delete(User, .{ .test_value = "foo", .test_num = undefined, .test_bool = true });
        try delete.send();
    }
}

test "Database: DeleteAll" {
    const allocator = std.testing.allocator;
    var db = Database.init(allocator);
    defer db.deinit();

    try db.connect("postgresql://postgres:postgres@localhost:5432/orm");

    const User = struct {
        pub const Table = "test_table";

        test_value: []const u8,
        test_num: ?i32,
        test_bool: bool,
    };

    {
        var deleteAll = db.deleteAll(User);
        try deleteAll.send();
    }
}
