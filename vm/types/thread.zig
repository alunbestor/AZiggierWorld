const Address = @import("program.zig").Address;

pub const ExecutionState = union(enum) {
    /// The thread is active and will continue execution from the specified address when it is next run.
    active: Address,

    /// The thread is inactive and cannot run, regardless of whether it is running or suspended.
    inactive: void,
};

pub const SuspendState = enum {
    /// The thread is not suspended: it will run if it is also active (see `ExecutionState`).
    running,

    /// The thread is paused and will not execute until unsuspended.
    suspended,
};

/// One of the 64 threads within the Another World virtual machine.
/// A thread maintains its own paused/running state and its current program counter.
/// Each tic, the virtual machine runs each active thread: the thread resumes executing the current program
/// starting from the thread's last program counter, and will run until the thread yields to the next thread
/// or deactivates itself.
pub const Thread = struct {
    /// The maximum number of program instructions that can be executed on a single thread in a single tic
    /// before it will abort with an error.
    /// Exceeding this number of instructions likely indicates an infinite loop.
    const max_executions_per_tic = 10_000;

    // Theoretically, a thread can only be in three functional states:
    // 1. Running at program counter X
    // 2. Suspended at program counter X
    // 3. Inactive
    //
    // However, Another World represents these 3 states with two booleans that can be modified independently of each other.
    // So there are actually 4 logical states:
    // 1. Running at program counter X and not suspended
    // 2. Running at program counter X and suspended
    // 3. Inactive and not suspended
    // 4. Inactive and suspended
    // States 3 and 4 have the same effect; but we cannot rule out that a program will suspend an inactive thread, then start running the thread *but expect it to remain suspended*. To allow that, we must track each variable independently.

    /// The active/inactive execution state of this thread during the current game tic.
    execution_state: ExecutionState = .inactive,
    /// The scheduled active/inactive execution state of this thread for the next game tic.
    /// If `null`, the current state will continue unchanged next tic.
    scheduled_execution_state: ?ExecutionState = null,

    /// The running/suspended state of this thread during the current game tic.
    suspend_state: SuspendState = .running,
    /// The scheduled running/suspended state of this thread for the current game tic.
    /// If `null`, the current state will continue unchanged next tic.
    scheduled_suspend_state: ?SuspendState = null,

    /// On the next game tic, activate this thread and jump to the specified address.
    /// If the thread is currently inactive, then it will remain so for the rest of the current tic.
    pub fn scheduleJump(self: *Thread, address: Address) void {
        self.scheduled_execution_state = ExecutionState { .active = address };
    }

    /// On the next game tic, deactivate this thread.
    /// If the thread is currently active, then it will remain so for the rest of the current tic.
    pub fn scheduleDeactivate(self: *Thread) void {
        self.scheduled_execution_state = .inactive;
    }

    /// On the next game tic, resume running this thread.
    /// If the thread is currently suspended, then it will remain so for the rest of the current tic.
    pub fn scheduleResume(self: *Thread) void {
        self.scheduled_suspend_state = .running;
    }

    /// On the next game tic, suspend this thread.
    /// If the thread is currently active and running, then it will still run for the current tic if it hasn't already.
    pub fn scheduleSuspend(self: *Thread) void {
        self.scheduled_suspend_state = .suspended;
    }

    /// Apply any excheduled changes to the thread's execution and suspend states.
    pub fn update(self: *Thread) void {
        if (self.scheduled_execution_state) |new_state| {
            self.execution_state = new_state;
            self.scheduled_execution_state = null;
        }

        if (self.scheduled_suspend_state) |new_state| {
            self.suspend_state = new_state;
            self.scheduled_suspend_state = null;
        }
    }
};

// -- Tests --

const testing = @import("std").testing;

test "scheduleJump schedules activation with specified program counter for next tic" {
    var thread = Thread { };

    thread.scheduleJump(0xDEAD);

    testing.expectEqual(thread.execution_state, .inactive);
    testing.expectEqual(thread.scheduled_execution_state, ExecutionState { .active = 0xDEAD, });
}

test "scheduleDeactivate schedules deactivation for next tic" {
    var thread = Thread { .execution_state = ExecutionState { .active = 0xDEAD } };

    thread.scheduleDeactivate();

    testing.expectEqual(thread.execution_state, ExecutionState { .active = 0xDEAD });
    testing.expectEqual(thread.scheduled_execution_state, .inactive);
}

test "scheduleResume schedules resuming for next tic" {
    var thread = Thread { .suspend_state = .suspended };

    thread.scheduleResume();

    testing.expectEqual(thread.suspend_state, .suspended);
    testing.expectEqual(thread.scheduled_suspend_state, .running);
}

test "scheduleSuspend schedules suspending for next tic" {
    var thread = Thread { };

    thread.scheduleSuspend();

    testing.expectEqual(thread.suspend_state, .running);
    testing.expectEqual(thread.scheduled_suspend_state, .suspended);
}

test "update applies scheduled execution state" {
    var thread = Thread { };

    thread.scheduleJump(0xDEAD);
    testing.expectEqual(thread.execution_state, .inactive);
    testing.expectEqual(thread.scheduled_execution_state, ExecutionState { .active = 0xDEAD });

    thread.update();
    testing.expectEqual(thread.execution_state, ExecutionState { .active = 0xDEAD });
    testing.expectEqual(thread.scheduled_execution_state, null);

    thread.scheduleDeactivate();
    testing.expectEqual(thread.execution_state, ExecutionState { .active = 0xDEAD });
    testing.expectEqual(thread.scheduled_execution_state, .inactive);

    thread.update();
    testing.expectEqual(thread.execution_state, .inactive);
    testing.expectEqual(thread.scheduled_execution_state, null);
}

test "update applies scheduled suspend state" {
    var thread = Thread { };

    testing.expectEqual(thread.suspend_state, .running);
    testing.expectEqual(thread.scheduled_suspend_state, null);

    thread.scheduleSuspend();
    testing.expectEqual(thread.suspend_state, .running);
    testing.expectEqual(thread.scheduled_suspend_state, .suspended);

    thread.update();
    testing.expectEqual(thread.suspend_state, .suspended);
    testing.expectEqual(thread.scheduled_suspend_state, null);

    thread.scheduleResume();
    testing.expectEqual(thread.suspend_state, .suspended);
    testing.expectEqual(thread.scheduled_suspend_state, .running);

    thread.update();
    testing.expectEqual(thread.suspend_state, .running);
    testing.expectEqual(thread.scheduled_suspend_state, null);
}
