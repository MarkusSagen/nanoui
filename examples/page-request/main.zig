//! Run tools/page-request-demo.py for a loopback server and hidden capture.
const std = @import("std");
const builtin = @import("builtin");
const nanoui = @import("nanoui");

const Demo = struct {
    app: *nanoui.App,
    window: ?*nanoui.Window = null,
    url: []const u8,
    capture: ?[]const u8,
    check: bool,

    fn start(raw: ?*anyopaque) callconv(.c) void {
        const s: *Demo = @ptrCast(@alignCast(raw.?));
        // Test credential only. Real apps obtain this off the UI thread.
        s.window.?.loadPageRequest(.{ .url = s.url, .headers = &.{.{ .name = "Authorization", .value = "Bearer nanoui-demo" }} }) catch |err| {
            std.log.err("navigation: {s}", .{@errorName(err)});
            s.app.quit();
        };
    }

    pub fn ready(s: *Demo) void {
        std.debug.print("demo: authenticated document ready\n", .{});
        if (comptime builtin.os.tag == .macos) {
            if (s.capture) |path| {
                @import("capture.zig").save(s.app, s.window.?.page.?.webview, path);
                return;
            }
        }
        if (s.check) s.app.quit();
    }
};

pub fn main(init: std.process.Init) !void {
    const app = try nanoui.App.create(init, .{ .name = "Deferred page request" });
    defer app.destroy();
    var demo: Demo = .{
        .app = app,
        .url = init.environ_map.get("NANOUI_DEMO_URL") orelse "http://127.0.0.1:8787/",
        .capture = init.environ_map.get("NANOUI_DEMO_CAPTURE"),
        .check = init.environ_map.get("NANOUI_DEMO_CHECK") != null,
    };
    try app.bind(&demo);
    demo.window = try app.newWindow(.{
        .title = "Deferred first request",
        .width = 900,
        .height = 720,
        .content = .{ .page = .{ .url = demo.url, .defer_initial_load = true, .private = true } },
    });
    nanoui.App.after(800, &demo, Demo.start);
    try app.run();
}
