//! WebView2 GET requests, separate from controller and callback ownership.
const std = @import("std");
const wv = @import("windows/webview2.zig");
const request_mod = @import("page_request.zig");
const page_mod = @import("page.zig");
const Com = wv.Com;
const iid_view: wv.Guid = .{ .a = 0x9e8f0cf8, .b = 0xe670, .c = 0x4b5e, .d = .{ 0xb2, 0xbc, 0x73, 0xe0, 0x61, 0xe3, 0x18, 0x4c } };
const iid_env: wv.Guid = .{ .a = 0x41f3632b, .b = 0x5ef4, .c = 0x404f, .d = .{ 0xad, 0x82, 0x2d, 0x60, 0x6c, 0x5a, 0x9a, 0x21 } };

pub fn load(self: anytype, req: request_mod.Request) !void {
    try request_mod.validate(req);
    const view = self.webview orelse return error.PageNotReady;
    var arena = std.heap.ArenaAllocator.init(self.queue.gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const buf = try a.alloc(u8, req.url.len + page_mod.origin.len + 1);
    const url = try std.unicode.utf8ToUtf16LeAllocZ(a, page_mod.fullUrl(buf, req.url));
    if (req.headers.len == 0) {
        if (wv.WebView.navigate(view, url) < 0) return error.NavigationFailed;
    } else {
        const extended = wv.query(view, &iid_view) orelse return error.RequestHeadersUnsupported;
        defer extended.release();
        const env = wv.query(self.environment orelse return error.PageNotReady, &iid_env) orelse return error.RequestHeadersUnsupported;
        defer env.release();
        var text: std.Io.Writer.Allocating = .init(a);
        for (req.headers) |h| try text.writer.print("{s}: {s}\r\n", .{ h.name, h.value });
        const headers = try std.unicode.utf8ToUtf16LeAllocZ(a, text.written());
        var request: ?*Com = null;
        // ICoreWebView2Environment2 slot 8, verified against SDK 1.0.4191.47.
        const make = env.slot(*const fn (*Com, [*:0]const u16, [*:0]const u16, ?*Com, [*:0]const u16, *?*Com) callconv(.winapi) wv.HRESULT, 8);
        if (make(env, url, std.unicode.utf8ToUtf16LeStringLiteral("GET"), null, headers, &request) < 0) return error.NavigationFailed;
        const native = request orelse return error.NavigationFailed;
        defer native.release();
        // ICoreWebView2_2 slot 63, NavigateWithWebResourceRequest.
        const navigate = extended.slot(*const fn (*Com, *Com) callconv(.winapi) wv.HRESULT, 63);
        if (navigate(extended, native) < 0) return error.NavigationFailed;
    }
    if (!self.queue.dead) {
        self.queue.setCurrent(req.url);
        self.queue.dom_ready = false;
    }
}
