//! Snapshot only this hidden WKWebView, never the screen.
const std = @import("std");
const nanoui = @import("nanoui");
const objc = nanoui.objc;
const Capture = struct {
    app: *nanoui.App,
    path: []const u8,

    fn done(s: *Capture, image: ?objc.Object, err: ?objc.Object) void {
        defer std.heap.page_allocator.destroy(s);
        defer s.app.quit();
        if (err != null or image == null) {
            std.log.err("webview capture failed", .{});
            return;
        }
        const pool = objc.Pool.push();
        defer pool.pop();
        const tiff = objc.msg(objc.Object, image.?, "TIFFRepresentation", .{});
        const bitmap = objc.msg(objc.Object, objc.alloc("NSBitmapImageRep"), "initWithData:", .{tiff});
        defer objc.release(bitmap);
        const properties = objc.msg(objc.Object, objc.class("NSDictionary"), "dictionary", .{});
        const png = objc.msg(objc.Object, bitmap, "representationUsingType:properties:", .{ @as(usize, 4), properties });
        if (!objc.msg(bool, png, "writeToFile:atomically:", .{ objc.nsString(s.path), true })) std.log.err("writing capture failed", .{});
    }
};

pub fn save(app: *nanoui.App, webview: objc.Object, path: []const u8) void {
    const s = std.heap.page_allocator.create(Capture) catch return;
    s.* = .{ .app = app, .path = path };
    var block = objc.Block(Capture, &.{ ?objc.Object, ?objc.Object }).init(s, Capture.done);
    objc.msg(void, webview, "takeSnapshotWithConfiguration:completionHandler:", .{ @as(?objc.Object, null), &block });
}
