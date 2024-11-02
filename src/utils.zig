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

/// Set everything to Optional by default and assign by default
/// Objects using this type do not need to be initialized with null
pub fn Partial(comptime T: type) type {
    if (!@hasDecl(T, .@"struct")) {
        @compileError("Cannot make Partial of " ++ @typeName(T) ++ ", it is not a struct");
    }

    const info = @typeInfo(T);
    comptime var fields: []const std.builtin.Type.StructField = &[_]std.builtin.Type.StructField{};
    inline for (info.@"struct".fields) |field| {
        const optional_type = switch (@typeInfo(field.type)) {
            .optional => field.type,
            else => ?field.type,
        };

        const default_value: optional_type = null;
        const aligned_ptr: *align(field.alignment) const anyopaque = @alignCast(@ptrCast(&default_value));

        const optional_field: [1]std.builtin.Type.StructField = [_]std.builtin.Type.StructField{.{
            .alignment = field.alignment,
            .default_value = aligned_ptr,
            .is_comptime = field.is_comptime,
            .name = field.name,
            .type = optional_type,
        }};

        fields = fields ++ optional_field;
    }

    const type_info: std.builtin.Type = .{
        .@"struct" = .{
            .backing_integer = info.@"struct".backing_integer,
            .decls = &[_]std.builtin.Type.Declaration{},
            .fields = fields,
            .is_tuple = info.@"struct".is_tuple,
            .layout = info.@"struct".layout,
        },
    };

    return @Type(type_info);
}
