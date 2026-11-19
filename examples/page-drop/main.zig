//! macOS host file drops, with a file-picker alternative. For a deterministic
//! hidden capture, tools/page-drop-demo.py invokes the AppKit destination
//! methods with private in-process drag objects, not a real Finder gesture.
const std = @import("std");
const builtin = @import("builtin");
const nanoui = @import("nanoui");
const objc = nanoui.objc;
const Files = nanoui.Event("files", struct { names: []const []const u8, source: []const u8 });

const Demo = struct {
    app: *nanoui.App,
    window: ?*nanoui.Window = null,
    capture: ?[]const u8,
    fixture: ?[]const u8,
    delivered: usize = 0,

    fn dropped(raw: ?*anyopaque, event: nanoui.PageFileDrop) void {
        const s: *Demo = @ptrCast(@alignCast(raw.?));
        s.delivered += 1;
        std.debug.print("demo: drop {d}, {d} files at {d},{d}\n", .{ s.delivered, event.urls.len, event.point.x, event.point.y });
        var arena = std.heap.ArenaAllocator.init(s.app.gpa);
        defer arena.deinit();
        const a = arena.allocator();
        const names = a.alloc([]const u8, event.urls.len) catch return;
        // Forward display names, not filesystem access, to this page.
        for (event.urls, names) |url, *name| {
            const nsurl = objc.msg(objc.Object, objc.class("NSURL"), "URLWithString:", .{objc.nsString(url)});
            name.* = a.dupe(u8, objc.fromNSString(objc.msg(objc.Object, nsurl, "lastPathComponent", .{}))) catch return;
        }
        Files.emit(s.window.?, .{ .names = names, .source = if (s.fixture != null) "In-process AppKit test drop" else "Native file drop" });
    }

    pub fn ready(s: *Demo) void {
        if (s.fixture != null) nanoui.App.after(200, s, inject);
    }

    fn inject(raw: ?*anyopaque) callconv(.c) void {
        const s: *Demo = @ptrCast(@alignCast(raw.?));
        const pool = objc.Pool.push();
        defer pool.pop();
        const a = s.app.gpa;
        const first = std.fs.path.join(a, &.{ s.fixture.?, "Track 01.wav" }) catch return;
        defer a.free(first);
        const second = std.fs.path.join(a, &.{ s.fixture.?, "Cover Art.png" }) catch return;
        defer a.free(second);
        const view = s.window.?.page.?.webview;
        var fixture: @import("fixture.zig").Fixture = undefined;
        fixture.init(view, &.{ first, second });
        defer fixture.deinit();
        _ = objc.msg(usize, view, "draggingEntered:", .{fixture.info});
        if (!objc.msg(bool, view, "performDragOperation:", .{fixture.info})) std.log.err("fixture drop rejected", .{});
    }

    pub fn choose(s: *Demo) !void {
        const paths = try nanoui.dialog.open(s.app.gpa, .{ .multiple = true });
        if (paths) |picked| {
            defer nanoui.dialog.freePaths(s.app.gpa, picked);
            const names = try s.app.gpa.alloc([]const u8, picked.len);
            defer s.app.gpa.free(names);
            for (picked, names) |path, *name| name.* = std.fs.path.basename(path);
            Files.emit(s.window.?, .{ .names = names, .source = "File picker" });
        }
    }

    pub fn captured(s: *Demo) void {
        if (s.capture) |path| @import("capture.zig").save(s.app, s.window.?.page.?.webview, path);
    }
};

pub fn main(init: std.process.Init) !void {
    if (comptime builtin.os.tag != .macos) {
        std.log.info("page-drop MVP requires macOS (page_file_drop_supported = false)", .{});
    } else {
        const app = try nanoui.App.create(init, .{ .name = "Webview file drops" });
        defer app.destroy();
        var demo: Demo = .{ .app = app, .capture = init.environ_map.get("NANOUI_DEMO_CAPTURE"), .fixture = init.environ_map.get("NANOUI_DROP_FIXTURE") };
        try app.bind(&demo);
        try app.registerEvent(Files);
        demo.window = try app.newWindow(.{
            .title = "Webview file drops",
            .width = 900,
            .height = 700,
            .content = .{ .page = .{
                .private = true,
                .file_drop = .{ .ctx = &demo, .on_drop = Demo.dropped },
                .assets = &.{.{ .path = "/index.html", .data = @embedFile("index.html") }},
            } },
        });
        try app.run();
    }
}
