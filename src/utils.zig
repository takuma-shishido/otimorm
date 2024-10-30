const std = @import("std");

pub fn isString(value: anytype) ?[]const u8 {
    const Info = @typeInfo(@TypeOf(value));
    switch (Info) {
        .pointer => |p| {
            if (p.size == .Slice and p.child == u8) {
                return value;
            } else {
                return isString(value.*);
            }
        },
        .array => |arr| {
            if (arr.child == u8) {
                return value[0..];
            }
        },
        .optional => {
            if (value) |val| {
                return isString(val);
            } else {
                return null;
            }
        },
        else => {
            return null;
        },
    }
    return null;
}

pub fn isNull(value: anytype) bool {
    const Info = @typeInfo(@TypeOf(value));
    switch (Info) {
        .pointer => |p| {
            return p.size == .One and p.child == void;
        },
        .optional => {
            return value == null;
        },
        else => {
            return false;
        },
    }
}
