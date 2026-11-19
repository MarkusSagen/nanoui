//! Real hidden WKWebView, in-process AppKit drag objects, private data.
//! No system drag session, pasteboard, mouse, keyboard or user files.
const std = @import("std");
const objc = @import("objc.zig");
const App = @import("app.zig").App;
const Window = @import("window.zig").Window;
const FileDrop = @import("window_types.zig").PageFileDrop;
const testing = std.testing;

const Fixture = struct {
    array: objc.Object,
    pb: objc.Object,
    info: objc.Object,
    point: objc.CGPoint,
    mask: usize = 1,

    fn read(obj: objc.Object, _: objc.SEL, _: objc.Object, _: ?objc.Object) callconv(.c) objc.Object {
        return objc.getZig(Fixture, obj).?.array;
    }
    fn pasteboard(obj: objc.Object, _: objc.SEL) callconv(.c) objc.Object {
        return objc.getZig(Fixture, obj).?.pb;
    }
    fn location(obj: objc.Object, _: objc.SEL) callconv(.c) objc.CGPoint {
        return objc.getZig(Fixture, obj).?.point;
    }
    fn operation(obj: objc.Object, _: objc.SEL) callconv(.c) usize {
        return objc.getZig(Fixture, obj).?.mask;
    }
    fn init(f: *Fixture, view: objc.Object) void {
        const pb_class = objc.defineClass(.{ .name = "NanoUITestDropPasteboard", .methods = &.{.{ .name = "readObjectsForClasses:options:", .imp = &read, .types = "@@:@@" }} });
        const info_class = objc.defineClass(.{ .name = "NanoUITestDropInfo", .methods = &.{
            .{ .name = "draggingPasteboard", .imp = &pasteboard, .types = "@@:" },
            .{ .name = "draggingLocation", .imp = &location, .types = "{CGPoint=dd}@:" },
            .{ .name = "draggingSourceOperationMask", .imp = &operation, .types = "Q@:" },
        } });
        const urls = objc.msg(objc.Object, objc.class("NSMutableArray"), "array", .{});
        for ([_][]const u8{ "file:///tmp/Track%2001.wav", "https://example.test/ignored", "file:///tmp/Track%2002.wav" }) |url| {
            objc.msg(void, urls, "addObject:", .{objc.msg(objc.Object, objc.class("NSURL"), "URLWithString:", .{objc.nsString(url)})});
        }
        f.* = .{
            .array = urls,
            .pb = objc.msg(objc.Object, pb_class, "new", .{}),
            .info = objc.msg(objc.Object, info_class, "new", .{}),
            .point = objc.msg(objc.CGPoint, view, "convertPoint:toView:", .{ objc.CGPoint{ .x = 65, .y = 95 }, @as(?objc.Object, null) }),
        };
        objc.setZig(f.pb, f);
        objc.setZig(f.info, f);
    }
    fn deinit(f: *Fixture) void {
        objc.release(f.pb);
        objc.release(f.info);
    }
};

const State = struct {
    window: ?*Window = null,
    calls: usize = 0,
    count: usize = 0,
    point: @import("ui/ui.zig").Point = .{},
    copy: ?[]u8 = null,
    close: bool = false,
    pump: bool = false,

    fn dropped(raw: ?*anyopaque, event: FileDrop) void {
        const s: *State = @ptrCast(@alignCast(raw.?));
        s.calls += 1;
        s.count = event.urls.len;
        s.point = event.point;
        s.copy = testing.allocator.dupe(u8, event.urls[0]) catch unreachable;
        if (s.pump) s.window.?.page.?.enqueue("{}", false);
        if (s.close) s.window.?.close();
        if (s.pump) @import("platform.zig").runFor(0.02);
    }
};

fn makeApp() !*App {
    const app = try testing.allocator.create(App);
    app.* = .{ .gpa = testing.allocator, .io = testing.io, .options = .{ .quit_on_last_window_closed = false }, .nsapp = objc.msg(objc.Object, objc.class("NSApplication"), "sharedApplication", .{}), .delegate = objc.new("NSObject"), .flags = .{ .hidden = true } };
    return app;
}
fn freeApp(app: *App) void {
    while (app.windows.items.len > 0) app.windows.items[app.windows.items.len - 1].close();
    app.windows.deinit(app.gpa);
    objc.release(app.delegate);
    app.gpa.destroy(app);
}

test "webview file drop batches local URLs, copies survive and coordinates are view points" {
    const pool = objc.Pool.push();
    defer pool.pop();
    const app = try makeApp();
    defer freeApp(app);
    var state: State = .{};
    defer if (state.copy) |s| testing.allocator.free(s);
    const w = try app.newWindow(.{ .visible = false, .width = 400, .height = 300, .content = .{ .page = .{ .private = true, .file_drop = .{ .ctx = &state, .on_drop = State.dropped } } } });
    const view = w.page.?.webview;
    var f: Fixture = undefined;
    f.init(view);
    defer f.deinit();
    try testing.expectEqual(@as(usize, 1), objc.msg(usize, view, "draggingEntered:", .{f.info}));
    try testing.expect(objc.msg(bool, view, "prepareForDragOperation:", .{f.info}));
    try testing.expectEqual(@as(usize, 0), state.calls);
    try testing.expect(objc.msg(bool, view, "performDragOperation:", .{f.info}));
    try testing.expectEqual(@as(usize, 1), state.calls);
    try testing.expectEqual(@as(usize, 2), state.count);
    try testing.expectEqualStrings("file:///tmp/Track%2001.wav", state.copy.?);
    try testing.expectApproxEqAbs(@as(f32, 65), state.point.x, 0.1);
    try testing.expectApproxEqAbs(@as(f32, 95), state.point.y, 0.1);
    try testing.expectEqual(@as(usize, 0), w.page.?.active_drops);
}

test "webview file drop callback can close the owning window" {
    const pool = objc.Pool.push();
    defer pool.pop();
    const app = try makeApp();
    defer freeApp(app);
    var state: State = .{ .close = true, .pump = true };
    defer if (state.copy) |s| testing.allocator.free(s);
    const w = try app.newWindow(.{ .visible = false, .content = .{ .page = .{ .private = true, .file_drop = .{ .ctx = &state, .on_drop = State.dropped } } } });
    state.window = w;
    const view = w.page.?.webview;
    _ = objc.retain(view);
    defer objc.release(view);
    var f: Fixture = undefined;
    f.init(view);
    defer f.deinit();
    try testing.expect(objc.msg(bool, view, "performDragOperation:", .{f.info}));
    try testing.expectEqual(@as(usize, 1), state.calls);
    try testing.expectEqual(@as(usize, 0), app.windows.items.len);
    try testing.expect(objc.getZig(@import("page_webkit.zig").Page, view) == null);
}
