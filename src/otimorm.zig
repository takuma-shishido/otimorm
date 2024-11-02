const std = @import("std");
const build_options = @import("build_options");

const pg = @import("pg");
const utils = @import("utils.zig");
const Partial = @import("utils.zig").Partial;
const Query = @import("query/lib.zig");

const log = std.log.scoped(.otimorm);

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
    _prepare: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .connected = false,
            ._pool = undefined,
            ._prepare = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.connected) {
            self._pool.deinit();
        }
        self._prepare.deinit();
    }

    pub fn prepareQuery(self: *Self, query: []const u8) !void {
        try self._prepare.append(query);
    }

    pub fn exec(self: Self, query: []const u8) !Result {
        if (!self.connected)
            return Error.NotConnected;

        if (build_options.debug_log) log.debug("exec: {s}", .{query});

        const conn = try self._pool.acquire();

        for (self._prepare.items) |item| {
            _ = conn.exec(item, .{}) catch |err| {
                if (err == error.PG) {
                    if (conn.err) |pge| {
                        std.log.err("prepare query error: {s}\n", .{pge.message});
                    }
                }
                return err;
            };
        }

        const result = conn.queryOpts(query, .{}, .{ .column_names = true, .release_conn = true }) catch |err| {
            if (err == error.PG) {
                if (conn.err) |pge| {
                    std.log.err("query error: {s}\n", .{pge.message});
                }
            }
            return err;
        };

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

    pub fn insert(self: *Self, comptime T: type, value: Partial(T)) Query.Insert(T) {
        return Query.Insert(T).init(self.allocator, self, value);
    }

    pub fn update(self: *Self, comptime T: type, value: Partial(T)) Query.Update(T) {
        return Query.Update(T).init(self.allocator, self, value);
    }

    pub fn delete(self: *Self, comptime T: type, value: Partial(T)) Query.Delete(T) {
        return Query.Delete(T).init(self.allocator, self, value);
    }

    pub fn deleteAll(self: *Self, comptime T: type) Query.DeleteAll(T) {
        return Query.DeleteAll(T).init(self.allocator, self);
    }
};
