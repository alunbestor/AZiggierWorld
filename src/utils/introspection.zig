//! Tools to make type introspection less painful and wordy.

const std = @import("std");

/// Given an integer type, returns the number of bits in that integer.
pub const bitCount = std.meta.bitCount;

/// Casts an integer type to another, returning an error on overflow (instead of trapping like @intCast).
pub const intCast = std.math.cast;

/// Given an integer type, returns the type used for legal left/right-shift operations.
pub const ShiftType = std.math.Log2Int;

/// The version of intToEnum in the Zig 0.9.1 Standard Library doesn't correctly handle
/// non-exhaustive enums.
pub fn intToEnum(comptime EnumTag: type, tag_int: anytype) std.meta.IntToEnumError!EnumTag {
    const enum_info = @typeInfo(EnumTag).Enum;

    if (enum_info.is_exhaustive) {
        inline for (enum_info.fields) |f| {
            const this_tag_value = @field(EnumTag, f.name);
            if (tag_int == @enumToInt(this_tag_value)) {
                return this_tag_value;
            }
        }

        return error.InvalidEnumTag;
    } else {
        const max = std.math.maxInt(enum_info.tag_type);
        const min = std.math.minInt(enum_info.tag_type);

        if (tag_int >= min and tag_int <= max) {
            return @intToEnum(EnumTag, tag_int);
        } else {
            return error.InvalidEnumTag;
        }
    }
}

/// If given a pointer type, returns the type that the pointer points to;
/// if given any other type, returns the base type.
/// Intended to simplify the introspection of `anytype` parameters that may be passed by reference or by value.
pub fn BaseType(comptime pointer_or_type: type) type {
    const type_info = @typeInfo(pointer_or_type);
    return switch (type_info) {
        .Pointer => |info| info.child,
        else => pointer_or_type,
    };
}

/// Given a function reference, introspects the return type of that function.
pub fn ReturnType(comptime function: anytype) type {
    const type_info = @typeInfo(@TypeOf(function));
    return switch (type_info) {
        .Fn => |info| info.return_type.?,
        .BoundFn => |info| info.return_type.?,
        else => @compileError("Parameter was not a function or bound function"),
    };
}

/// Given a function that returns a regular type, an optional (`?payload`)
/// or an error union (`error_set!payload`), returns the type of the payload.
pub fn PayloadType(comptime function: anytype) type {
    const return_type = ReturnType(function);
    return switch (@typeInfo(return_type)) {
        .ErrorUnion => |info| info.payload,
        .Optional => |info| info.child,
        else => return_type,
    };
}

/// Given a function that returns an error union (`error_set!payload`),
/// returns the type of the error set.
/// Returns a compile error if the function does not return an error union.
pub fn ErrorType(comptime function: anytype) type {
    const return_type = ReturnType(function);
    return switch (@typeInfo(return_type)) {
        .ErrorUnion => |info| info.error_set,
        else => @compileError("Parameter did not return an ErrorUnion"),
    };
}

// -- Tests --

const testing = @import("testing.zig");

test "bitCount returns number of bits in integer" {
    try testing.expectEqual(0, bitCount(u0));
    try testing.expectEqual(1, bitCount(u1));
    try testing.expectEqual(4, bitCount(u4));
    try testing.expectEqual(8, bitCount(u8));
    try testing.expectEqual(16, bitCount(u16));
    try testing.expectEqual(32, bitCount(u32));
    try testing.expectEqual(64, bitCount(u64));
}

test "bitCount triggers compile error when passed non-integer" {
    // Uncomment me to trigger a compile error!
    //_ = bitCount(struct {});
}

test "ReturnType gets return type of free function" {
    const Namespace = struct {
        fn example() void {}
    };

    try testing.expectEqual(void, ReturnType(Namespace.example));
}

test "ReturnType gets return type of bound function" {
    const Struct = struct {
        const Self = @This();

        fn boundExample(_: Self) void {}
    };

    const foo = Struct{};
    try testing.expectEqual(void, ReturnType(foo.boundExample));
}

test "ReturnType triggers compile error when passed non-function type" {
    // Uncomment me to trigger a compile error!
    // _ = ReturnType(u32);
}

test "PayloadType gets return type of function that returns a type directly" {
    const Namespace = struct {
        fn example() u32 {
            return 0;
        }
    };

    try testing.expectEqual(u32, PayloadType(Namespace.example));
}

test "PayloadType gets return type of function that returns an optional" {
    const Namespace = struct {
        fn example() ?u32 {
            return null;
        }
    };

    try testing.expectEqual(u32, PayloadType(Namespace.example));
}

test "PayloadType gets return type of function that returns an error union" {
    const Namespace = struct {
        fn example() anyerror!u32 {
            return 0;
        }
    };

    try testing.expectEqual(u32, PayloadType(Namespace.example));
}

test "ErrorType gets return type of function that returns an error union" {
    const CustomError = error{FlagrantViolation};
    const Namespace = struct {
        fn example() CustomError!u32 {
            return 255;
        }
    };

    try testing.expectEqual(CustomError, ErrorType(Namespace.example));
}

test "ErrorType returns compile error when given function that does not return an error union" {
    // Uncomment to trigger a compile-time error!
    // const Namespace = struct {
    //     fn example() void {}
    // };

    //_ = ErrorType(Namespace.example);
}

test "BaseType returns struct type when given a pointer to a struct" {
    const MyStruct = struct { foo: usize };

    const pointer_to_struct: *MyStruct = undefined;

    try testing.expectEqual(MyStruct, BaseType(@TypeOf(pointer_to_struct)));
}

test "BaseType returns struct type when given a struct type" {
    const MyStruct = struct { foo: usize };

    const value_of_struct: MyStruct = undefined;

    try testing.expectEqual(MyStruct, BaseType(@TypeOf(value_of_struct)));
}

// -- intToEnum tests

const ExhaustiveEnumWithInferredTag = enum {
    first,
    second,
};

const ExhaustiveEnumWithExplicitTag = enum(i8) {
    first = 0,
    second = 1,
};

const NonExhaustiveEnum = enum(i8) {
    first = 0,
    second = 1,
    _,
};

const standardLibraryIntToEnum = std.meta.intToEnum;

test "intToEnum with non-exhaustive enum" {
    _ = try intToEnum(NonExhaustiveEnum, 0);
    _ = try intToEnum(NonExhaustiveEnum, 1);
    _ = try intToEnum(NonExhaustiveEnum, 127);
    _ = try intToEnum(NonExhaustiveEnum, -128);
    try testing.expectError(error.InvalidEnumTag, intToEnum(NonExhaustiveEnum, 256));
    try testing.expectError(error.InvalidEnumTag, intToEnum(NonExhaustiveEnum, -256));
}

test "intToEnum with exhaustive enum" {
    _ = try intToEnum(ExhaustiveEnumWithExplicitTag, 0);
    _ = try intToEnum(ExhaustiveEnumWithExplicitTag, 1);
    try testing.expectError(error.InvalidEnumTag, intToEnum(ExhaustiveEnumWithExplicitTag, 127));
    try testing.expectError(error.InvalidEnumTag, intToEnum(ExhaustiveEnumWithExplicitTag, -128));
    try testing.expectError(error.InvalidEnumTag, intToEnum(ExhaustiveEnumWithExplicitTag, 256));
    try testing.expectError(error.InvalidEnumTag, intToEnum(ExhaustiveEnumWithExplicitTag, -256));
}

test "intToEnum with exhaustive enum with inferred tag" {
    _ = try intToEnum(ExhaustiveEnumWithInferredTag, 0);
    _ = try intToEnum(ExhaustiveEnumWithInferredTag, 1);
    try testing.expectError(error.InvalidEnumTag, intToEnum(ExhaustiveEnumWithInferredTag, 127));
    try testing.expectError(error.InvalidEnumTag, intToEnum(ExhaustiveEnumWithInferredTag, -128));
    try testing.expectError(error.InvalidEnumTag, intToEnum(ExhaustiveEnumWithInferredTag, 256));
    try testing.expectError(error.InvalidEnumTag, intToEnum(ExhaustiveEnumWithInferredTag, -256));
}

test "Standard Library intToEnum has buggy handling of non-exhaustive enums" {
    _ = try standardLibraryIntToEnum(NonExhaustiveEnum, 0);
    _ = try standardLibraryIntToEnum(NonExhaustiveEnum, 1);
    try testing.expectError(error.InvalidEnumTag, standardLibraryIntToEnum(NonExhaustiveEnum, 256));
    try testing.expectError(error.InvalidEnumTag, standardLibraryIntToEnum(NonExhaustiveEnum, -256));

    // These two expectations will start failing once the bug is fixed upstream,
    // at which point we can get rid of our overridden implementation.
    try testing.expectError(error.InvalidEnumTag, standardLibraryIntToEnum(NonExhaustiveEnum, 127));
    try testing.expectError(error.InvalidEnumTag, standardLibraryIntToEnum(NonExhaustiveEnum, -128));
}
