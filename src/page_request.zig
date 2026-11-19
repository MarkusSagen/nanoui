//! A single GET navigation, not persistent request interception.
const std = @import("std");

pub const Header = struct { name: []const u8, value: []const u8 };
pub const Request = struct {
    url: []const u8,
    /// Only this navigation. Redirects follow the web engine's policy;
    /// custom headers are not a cross-origin credential isolation boundary.
    /// Cookie/Host and transport headers are rejected.
    headers: []const Header = &.{},
};

pub fn validate(req: Request) !void {
    if (req.url.len == 0 or std.mem.indexOfScalar(u8, req.url, 0) != null or !std.unicode.utf8ValidateSlice(req.url)) return error.InvalidUrl;
    if (req.headers.len > 0 and !std.mem.startsWith(u8, req.url, "http://") and !std.mem.startsWith(u8, req.url, "https://")) return error.HeadersRequireHttp;
    for (req.headers, 0..) |h, i| {
        if (h.name.len == 0) return error.InvalidHeader;
        for (req.headers[0..i]) |previous| if (std.ascii.eqlIgnoreCase(previous.name, h.name)) return error.DuplicateHeader;
        for (h.name) |ch| if (!std.ascii.isAlphanumeric(ch) and std.mem.indexOfScalar(u8, "!#$%&'*+-.^_`|~", ch) == null) return error.InvalidHeader;
        for (h.value) |ch| if ((ch < 32 and ch != '\t') or ch == 127) return error.InvalidHeader;
        if (!std.unicode.utf8ValidateSlice(h.value)) return error.InvalidHeader;
        for ([_][]const u8{ "Cookie", "Host", "Content-Length", "Transfer-Encoding", "Connection" }) |name| {
            if (std.ascii.eqlIgnoreCase(name, h.name)) return error.ReservedHeader;
        }
    }
}

/// Owns all request bytes, including headers, until consumed or replaced.
pub const Owned = struct {
    arena: std.heap.ArenaAllocator,
    request: Request,

    pub fn init(gpa: std.mem.Allocator, req: Request) !Owned {
        try validate(req);
        var arena = std.heap.ArenaAllocator.init(gpa);
        errdefer arena.deinit();
        const a = arena.allocator();
        const headers = try a.alloc(Header, req.headers.len);
        for (headers, req.headers) |*out, h| out.* = .{ .name = try a.dupe(u8, h.name), .value = try a.dupe(u8, h.value) };
        const url = try a.dupe(u8, req.url);
        return .{ .arena = arena, .request = .{ .url = url, .headers = headers } };
    }

    pub fn deinit(self: *Owned) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

/// The latest explicit request wins over automatic startup. Replacement
/// allocates first, so an invalid request or OOM preserves the old one.
pub const Pending = struct {
    owned: ?Owned = null,

    pub fn set(self: *Pending, gpa: std.mem.Allocator, req: Request) !void {
        const next = try Owned.init(gpa, req);
        self.deinit();
        self.owned = next;
    }

    pub fn take(self: *Pending) ?Owned {
        const out = self.owned;
        self.owned = null;
        return out;
    }

    pub fn deinit(self: *Pending) void {
        if (self.owned) |*o| o.deinit();
        self.owned = null;
    }
};

test "pending navigation owns bytes, replaces once and survives invalid replacement" {
    var pending: Pending = .{};
    defer pending.deinit();
    var value = "Bearer demo".*;
    try pending.set(std.testing.allocator, .{ .url = "https://example.test/first", .headers = &.{.{ .name = "Authorization", .value = &value }} });
    @memset(&value, 'x');
    try std.testing.expectEqualStrings("Bearer demo", pending.owned.?.request.headers[0].value);
    try std.testing.expectError(error.InvalidHeader, pending.set(std.testing.allocator, .{ .url = "https://example.test/", .headers = &.{.{ .name = "X-Test", .value = "a\r\nb" }} }));
    try std.testing.expectEqualStrings("https://example.test/first", pending.owned.?.request.url);
    try pending.set(std.testing.allocator, .{ .url = "/next" });
    var got = pending.take().?;
    defer got.deinit();
    try std.testing.expectEqualStrings("/next", got.request.url);
    try std.testing.expect(pending.take() == null);
}

test "navigation headers reject injection, reserved headers and non-HTTP URLs" {
    try std.testing.expectError(error.DuplicateHeader, validate(.{ .url = "https://example.test", .headers = &.{ .{ .name = "X-Test", .value = "a" }, .{ .name = "x-test", .value = "b" } } }));
    try std.testing.expectError(error.HeadersRequireHttp, validate(.{ .url = "/", .headers = &.{.{ .name = "Authorization", .value = "demo" }} }));
    try std.testing.expectError(error.InvalidHeader, validate(.{ .url = "https://example.test", .headers = &.{.{ .name = "Bad:Name", .value = "a" }} }));
    try std.testing.expectError(error.ReservedHeader, validate(.{ .url = "https://example.test", .headers = &.{.{ .name = "cookie", .value = "a=b" }} }));
}
