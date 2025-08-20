/// Get the underlying `enum` type from a tagged union
fn Tag(comptime Event: type) type {
    const info = @typeInfo(Event);

    if (info == .@"union") {
        if (info.@"union".tag_type) |tag_type| {
            return tag_type;
        }
    }

    @compileError("expected `union (enum)` as input");
}

/// Given an event type (tagged union), get the payload associated
/// to one of its tags
fn Payload(comptime Event: type, comptime tag: Tag(Event)) type {
    return @FieldType(Event, @tagName(tag));
}

/// Signature of a callback function for a given tag
fn CallbackFn(comptime Event: type, comptime tag: Tag(Event)) type {
    return *const fn (Payload(Event, tag)) void;
}

/// Helper to get the fields from the underlying enum
fn eventFields(comptime Event: type) []const Type.EnumField {
    return @typeInfo(Tag(Event)).@"enum".fields;
}

/// Create a struct type from the given event type
/// 
/// It will have a field for each tag, which will store all callbacks
/// registered for such tag (in an `ArrayList`)
fn Subscriptions(comptime Event: type) type {
    var fields: []const Type.StructField = &.{};

    for (eventFields(Event)) |field| {
        const tag = @field(Tag(Event), field.name);
        const T = std.ArrayList(CallbackFn(Event, tag));

        fields = fields ++ &[_]Type.StructField{
            .{
                .name = field.name,
                .type = T,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = std.meta.alignment(T),
            },
        };
    }

    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

/// Create an event bus type for the given event type
///
/// The event type is a tagged union that describes the different
/// existing events, and the payload associated to each of them.
///
/// Example:
/// ```zig
/// const EventBus = pubsub.EventBus(union (enum) {
///     login: UserId,
///     logout: UserId,
///     message_sent: struct {
///         from: UserId,
///         to: UserId,
///         text: []cont u8
///     },
/// });
pub fn EventBus(comptime Event: type) type {
    return struct {
        allocator: std.mem.Allocator,
        subscriptions: Subscriptions(Event),

        fn callbacksFor(self: *Self, comptime tag: Tag(Event)) *std.ArrayList(CallbackFn(Event, tag)) {
            return &@field(self.subscriptions, @tagName(tag));
        }

        /// Initialize an instance of the event bus
        pub fn create(allocator: std.mem.Allocator) Self {
            var self: Self = .{
                .allocator = allocator,
                // SAFETY: initialized below
                .subscriptions = undefined,
            };

            inline for (eventFields(Event)) |field| {
                const tag = @field(Tag(Event), field.name);
                self.callbacksFor(tag).* = .empty;
            }

            return self;
        }

        /// Register a new callback for an event
        /// 
        /// Example:
        /// ```zig
        /// fn loginHandler(user: UserId) void {
        ///     // do something
        /// }
        /// 
        /// try bus.subscribe(.login, loginHandler);
        /// ```
        pub fn subscribe(self: *Self, comptime tag: Tag(Event), callback: CallbackFn(Event, tag)) !void {
            try self.callbacksFor(tag).append(self.allocator, callback);
        }

        /// Emit an event
        ///
        /// Example:
        /// ```zig
        /// bus.publish(.login, user.id);
        /// ```
        pub fn publish(self: *Self, comptime tag: Tag(Event), payload: Payload(Event, tag)) void {
            for (self.callbacksFor(tag).items) |callback| {
                callback(payload);
            }
        }

        const Self = @This();
    };
}

const std = @import("std");
const Type = std.builtin.Type;
