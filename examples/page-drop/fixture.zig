//! In-process AppKit input for hidden demonstrations; no system pasteboard.
const objc = @import("nanoui").objc;
pub const Fixture = struct {
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
    pub fn init(f: *Fixture, view: objc.Object, paths: []const []const u8) void {
        const pb_class = objc.defineClass(.{ .name = "NanoUIDemoDropPasteboard", .methods = &.{.{ .name = "readObjectsForClasses:options:", .imp = &read, .types = "@@:@@" }} });
        const info_class = objc.defineClass(.{ .name = "NanoUIDemoDropInfo", .methods = &.{
            .{ .name = "draggingPasteboard", .imp = &pasteboard, .types = "@@:" },
            .{ .name = "draggingLocation", .imp = &location, .types = "{CGPoint=dd}@:" },
            .{ .name = "draggingSourceOperationMask", .imp = &operation, .types = "Q@:" },
        } });
        const urls = objc.msg(objc.Object, objc.class("NSMutableArray"), "array", .{});
        for (paths) |path| {
            objc.msg(void, urls, "addObject:", .{objc.msg(objc.Object, objc.class("NSURL"), "fileURLWithPath:", .{objc.nsString(path)})});
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
    pub fn deinit(f: *Fixture) void {
        objc.release(f.pb);
        objc.release(f.info);
    }
};
