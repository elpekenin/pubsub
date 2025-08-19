fn Tag(comptime E: type) type {
    const info = @typeInfo(E);

    if (info == .@"union") {
        if (info.@"union".tag_type) |tag_type| {
            return tag_type;
        }
    }

    @compileError("expected `union (enum)` as input");
}

fn Payload(comptime E: type, comptime tag: Tag(E)) type {
    return @FieldType(E, @tagName(tag));
}

fn CallbackFn(comptime E: type, comptime tag: Tag(E)) type {
    return *const fn (Payload(E, tag)) void;
}

/// create an event bus for the given tagged union
pub fn EventBus(comptime E: type) type {
    const Subscription = struct {
        tag: Tag(E),
        /// can't have specific function type here because the specific tag is unknown at this point
        ///
        /// this is still safe(ish) because `.subscribe` ensures function is of type `CallbackFn(E, tag)`
        ///
        /// if user decides to add an entry manually, that's their problem ^^
        /// ```zig
        /// // DONT DO THIS, BREAKAGE INCOMING !!
        /// try bus.subscriptions.append(bus.allocator, .{
        ///     .tag = .tag_name,
        ///     .callback = invalidFunction,
        /// });
        /// ```
        callback: *const anyopaque,
    };

    return struct {
        allocator: std.mem.Allocator,
        subscriptions: std.ArrayList(Subscription),

        pub fn init(allocator: std.mem.Allocator) Bus {
            return .{
                .allocator = allocator,
                .subscriptions = .empty,
            };
        }

        pub fn subscribe(bus: *Bus, comptime tag: Tag(E), callback: CallbackFn(E, tag)) !void {
            try bus.subscriptions.append(bus.allocator, .{
                .tag = tag,
                .callback = callback,
            });
        }

        pub fn publish(bus: *const Bus, comptime tag: Tag(E), payload: Payload(E, tag)) void {
            for (bus.subscriptions.items) |subscription| {
                if (subscription.tag != tag) continue;

                const callback: CallbackFn(E, tag) = @ptrCast(subscription.callback);
                callback(payload);
            }
        }

        const Bus = @This();
    };
}

const std = @import("std");