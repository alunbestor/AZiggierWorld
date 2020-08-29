const Thread = @import("types/thread.zig").Thread;
const thread_id = @import("types/thread_id.zig");

pub const max_threads = 64;
pub const max_registers = 256;

/// Register values are interpreted as signed 16-bit integers.
pub const Register = i16;
pub const RegisterID = u8;

pub const VirtualMachine = struct {
    /// The current state of the VM's 64 threads.
    threads: [max_threads]Thread = [_]Thread { .{} } ** max_threads,

    /// The current state of the VM's 256 registers.
    registers: [max_registers]Register = [_]Register { 0 } ** max_registers,

    pub fn init() VirtualMachine {
        var vm = VirtualMachine { };

        // Initialize the main thread to begin execution at the start of the current program
        vm.threads[thread_id.main].execution_state = .{ .active = 0 };

        return vm;
    }
};

// -- Tests --

const testing = @import("../utils/testing.zig");

test "init creates new virtual machine with expected state" {
    const vm = VirtualMachine.init();

    for (vm.threads) |thread, id| {
        if (id == thread_id.main) {
            testing.expectEqual(.{ .active = 0 }, thread.execution_state);
        } else {
            testing.expectEqual(.inactive, thread.execution_state);
        }
        testing.expectEqual(.running, thread.suspend_state);
    }

    for (vm.registers) |register| {
        testing.expectEqual(0, register);
    }
}
