//! AppKit drops over WKWebView. Opt-in local files go to the host;
//! ordinary HTML drops and non-file content keep WebKit's implementation.
const std = @import("std");
const objc = @import("objc.zig");
const Page = @import("page_webkit.zig").Page;

pub const methods = [_]objc.Method{
    .{ .name = "draggingEntered:", .imp = &entered, .types = "Q@:@" },
    .{ .name = "draggingUpdated:", .imp = &updated, .types = "Q@:@" },
    .{ .name = "prepareForDragOperation:", .imp = &prepare, .types = "c@:@" },
    .{ .name = "performDragOperation:", .imp = &perform, .types = "c@:@" },
};

pub fn configure(view: objc.Object) void {
    const pool = objc.Pool.push();
    defer pool.pop();
    const existing = objc.msg(objc.Object, view, "registeredDraggedTypes", .{});
    const types = objc.msg(objc.Object, existing, "arrayByAddingObject:", .{objc.nsString("public.file-url")});
    objc.msg(void, view, "registerForDraggedTypes:", .{types});
}

/// Borrowed NSURL array; only read while the private caller pool is alive.
fn fileUrls(info: objc.Object) ?objc.Object {
    const pb = objc.msg(objc.Object, info, "draggingPasteboard", .{});
    const classes = objc.msg(objc.Object, objc.class("NSArray"), "arrayWithObject:", .{objc.class("NSURL")});
    return objc.msg(?objc.Object, pb, "readObjectsForClasses:options:", .{ classes, @as(?objc.Object, null) });
}

fn owns(view: objc.Object, info: objc.Object) bool {
    const s = objc.getZig(Page, view) orelse return false;
    if (s.queue.dead or s.queue.options.file_drop == null) return false;
    // A copy-only host must respect what the source offers.
    if (objc.msg(objc.NSUInteger, info, "draggingSourceOperationMask", .{}) & 1 == 0) return false;
    const urls = fileUrls(info) orelse return false;
    const n = objc.msg(usize, urls, "count", .{});
    for (0..n) |i| {
        const url = objc.msg(objc.Object, urls, "objectAtIndex:", .{i});
        if (objc.msg(bool, url, "isFileURL", .{})) return true;
    }
    return false;
}

fn entered(view: objc.Object, _: objc.SEL, info: objc.Object) callconv(.c) usize {
    const pool = objc.Pool.push();
    defer pool.pop();
    if (owns(view, info)) return 1;
    return objc.msgSuper(usize, view, objc.class("WKWebView"), "draggingEntered:", .{info});
}

fn updated(view: objc.Object, _: objc.SEL, info: objc.Object) callconv(.c) usize {
    const pool = objc.Pool.push();
    defer pool.pop();
    if (owns(view, info)) return 1;
    return objc.msgSuper(usize, view, objc.class("WKWebView"), "draggingUpdated:", .{info});
}

fn prepare(view: objc.Object, _: objc.SEL, info: objc.Object) callconv(.c) bool {
    const pool = objc.Pool.push();
    defer pool.pop();
    if (owns(view, info)) return true;
    return objc.msgSuper(bool, view, objc.class("WKWebView"), "prepareForDragOperation:", .{info});
}

fn perform(view: objc.Object, _: objc.SEL, info: objc.Object) callconv(.c) bool {
    const pool = objc.Pool.push();
    defer pool.pop();
    if (!owns(view, info)) return objc.msgSuper(bool, view, objc.class("WKWebView"), "performDragOperation:", .{info});
    const s = objc.getZig(Page, view) orelse return false;
    var arena = std.heap.ArenaAllocator.init(s.queue.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const urls = fileUrls(info) orelse return false;
    var out: std.ArrayList([]const u8) = .empty;
    for (0..objc.msg(usize, urls, "count", .{})) |i| {
        const url = objc.msg(objc.Object, urls, "objectAtIndex:", .{i});
        if (!objc.msg(bool, url, "isFileURL", .{})) continue;
        const str = objc.msg(objc.Object, url, "absoluteString", .{});
        out.append(a, a.dupe(u8, objc.fromNSString(str)) catch return false) catch return false;
    }
    if (out.items.len == 0) return false;
    const location = objc.msg(objc.CGPoint, info, "draggingLocation", .{});
    const p = objc.msg(objc.CGPoint, view, "convertPoint:fromView:", .{ location, @as(?objc.Object, null) });
    const bounds = objc.msg(objc.CGRect, view, "bounds", .{});
    const handler = s.queue.options.file_drop.?;
    s.active_drops += 1;
    defer s.endDrop();
    handler.on_drop(handler.ctx, .{
        .point = .{ .x = @floatCast(p.x - bounds.origin.x), .y = @floatCast(if (objc.msg(bool, view, "isFlipped", .{})) p.y - bounds.origin.y else bounds.size.height - (p.y - bounds.origin.y)) },
        .urls = out.items,
    });
    return true;
}
