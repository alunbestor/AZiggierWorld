const std = @import("std");
const SDL = @import("sdl2");

const anotherworld = @import("lib/anotherworld.zig");
const testing = @import("utils").testing;
const log = anotherworld.log;
const SDLEngine = @import("engines/sdl_engine.zig").SDLEngine;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // Read the path to Another World game files from the first command-line argument.
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // First argument is the path to the currently-running executable,
    // game path should be the second argument.
    // TODO: allow this to be read from an environment variable,
    // or default to a path relative to the executable.
    if (args.len < 2) {
        std.log.err("Provide the path to the Another World game directory as the first argument.", .{});
        return error.MissingGamePathArgument;
    }

    const game_path = args[1];
    var engine = try SDLEngine.init(allocator, game_path);
    defer engine.deinit();

    // Run the main loop until the user quits the application or closes the window.
    engine.runUntilExit() catch |err| {
        log.err("Virtual machine execution failed: {}", .{err});
        return err;
    };
}

test "Run all tests" {
    testing.refAllDecls(@import("integration_tests/all_tests.zig"));
    testing.refAllDecls(@import("lib/anotherworld.zig"));
}
