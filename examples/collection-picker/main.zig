//! The same collection picker on a native surface and in a browser.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const search = @import("shared_search");
const files = nanoui.file_picker;
const browser = @import("builtin").os.tag == .wasi;
const file_options: files.Options = .{ .extensions = &.{"txt"}, .max_bytes = 32 * 1024 };

const entries = [_]search.index.Input{
    .{ .id = "art", .label = "Art history" },
    .{ .id = "coffee", .label = "Café notebooks" },
    .{ .id = "design", .label = "Design references" },
    .{ .id = "japan", .label = "日本語の資料" },
    .{ .id = "music", .label = "Music scores" },
};

const Picker = struct {
    allocator: std.mem.Allocator,
    index: *search.Index,
    io: std.Io,
    window: ?*nanoui.Window = null,
    file_pending: bool = false,
    file_name: ui.TextBuffer = .{},
    file_size: usize = 0,
    file_preview: ui.TextBuffer = .{},
    file_message: []const u8 = "",
    query: ui.TextBuffer = .{},
    open: bool = false,
    trigger: u64 = 0,
    selected: usize = 0,
    chosen: ?u32 = null,
    results: [entries.len]u32 = undefined,
    count: usize = 0,
    failed: bool = false,

    fn update(s: *Picker) void {
        s.failed = false;
        s.count = 0;
        s.selected = 0;
        s.find() catch {
            s.failed = true;
        };
    }

    fn find(s: *Picker) !void {
        if (s.query.text().len == 0) {
            for (&s.results, 0..) |*item, i| item.* = @intCast(i);
            s.count = entries.len;
            return;
        }
        var session = try search.Session.init(s.allocator, s.index, s.query.text());
        defer session.deinit();
        while (session.phase == .strong or session.phase == .approximate) try session.step(16);
        if (session.phase != .complete) return error.SearchIncomplete;
        for (session.results.items, 0..) |item, i| s.results[i] = item.candidate;
        s.count = session.results.items.len;
    }

    fn show(s: *Picker, c: *ui.Context) void {
        s.open = true;
        s.query.clear();
        s.query.focus();
        s.update();
        c.changed = true;
    }

    fn close(s: *Picker, c: *ui.Context) void {
        s.open = false;
        c.focus = s.trigger;
        c.changed = true;
    }

    fn choose(s: *Picker, c: *ui.Context, candidate: u32) void {
        s.chosen = candidate;
        ui.access.announce(c, entries[candidate].label);
        s.close(c);
    }

    fn fileResult(ctx: ?*anyopaque, result: files.Result) void {
        const s: *Picker = @ptrCast(@alignCast(ctx.?));
        s.file_name.clear();
        s.file_preview.clear();
        s.file_message = switch (result) {
            .picked => |file| blk: {
                s.file_name.set(file.name);
                s.file_size = file.bytes.len;
                const first = file.bytes[0 .. std.mem.indexOfScalar(u8, file.bytes, '\n') orelse file.bytes.len];
                if (first.len <= 120 and std.unicode.utf8ValidateSlice(first)) s.file_preview.set(first);
                break :blk "";
            },
            .cancelled => "No file chosen",
            .failed => |failure| switch (failure) {
                .too_large => "The file exceeds 32 KiB",
                else => "Could not open the file",
            },
        };
    }

    fn openNative(ctx: ?*anyopaque) callconv(.c) void {
        const s: *Picker = @ptrCast(@alignCast(ctx.?));
        defer s.file_pending = false;
        if (s.window == null) return;
        const chosen = files.open(s.allocator, s.io, file_options) catch |err| blk: {
            fileResult(s, .{ .failed = if (err == error.FileTooLarge) .too_large else .io });
            break :blk null;
        };
        if (chosen) |file| {
            defer file.deinit(s.allocator);
            fileResult(s, .{ .picked = file.file });
        } else if (s.file_message.len == 0) {
            fileResult(s, .cancelled);
        }
        if (s.window) |win| win.redraw();
    }

    fn closed(ctx: *anyopaque, _: *nanoui.Window) void {
        const s: *Picker = @ptrCast(@alignCast(ctx));
        s.window = null;
    }

    fn fileControl(s: *Picker, c: *ui.Context) void {
        ui.key(c, "choose-text-file");
        const control = ui.div(c).row().p(8).rounded(6).bg(c.theme.surface).control();
        defer control.end();
        const label = "Choose text file";
        ui.access.describe(c, control.index, .{ .label = label, .enabled = !s.file_pending });
        const click = c.interact(control.index, .{ .focusable = true }).clicked;
        if (comptime browser) {
            files.bind(c, control.index, file_options, s, fileResult) catch {
                s.file_message = "File selection is unavailable";
            };
        } else if (click and !s.file_pending and s.window != null) {
            s.file_message = "";
            s.file_pending = nanoui.App.onMain(s, openNative);
            if (!s.file_pending) s.file_message = "Could not open the file";
        }
        ui.label(c, label);
    }

    fn view(s: *Picker, c: *ui.Context) void {
        c.focus_ring = .{ .color = c.theme.accent };
        const column = ui.div(c).column().wFull().p(18).gap(10);
        defer column.end();
        ui.label(c, "Collections");
        {
            ui.key(c, "open collections");
            const trigger = ui.div(c).row().p(8).rounded(6).bg(c.theme.surface).control();
            defer trigger.end();
            s.trigger = c.node(trigger.index).id;
            if (s.open) ui.access.hide(c, trigger.index) else ui.access.describe(c, trigger.index, .{ .label = "Choose collection" });
            if (c.interact(trigger.index, .{ .focusable = !s.open }).clicked and !s.open) s.show(c);
            ui.label(c, "Choose collection");
        }
        if (s.chosen) |candidate| ui.label(c, entries[candidate].label);
        if (!s.open and c.shortcut(.{ .key = 'k', .cmd = true })) s.show(c);
        if (!s.open) {
            s.fileControl(c);
            if (s.file_name.text().len > 0) ui.label(c, c.print("{s} ({d} bytes)", .{ s.file_name.text(), s.file_size }));
            if (s.file_preview.text().len > 0) ui.label(c, s.file_preview.text());
            if (s.file_message.len > 0) ui.label(c, s.file_message);
            return;
        }
        if (c.input.key == .escape) {
            c.input.key = null;
            s.close(c);
            return;
        }
        if (c.input.key == .down or c.input.key == .up) {
            if (s.count != 0) {
                s.selected = if (c.input.key == .down)
                    (s.selected + 1) % s.count
                else
                    (s.selected + s.count - 1) % s.count;
            }
            c.input.key = null;
        }
        const result = ui.textField(c, &s.query, .{ .placeholder = "Search collections", .width = .fill });
        if (result.changed) s.update();
        if (result.submitted and s.count != 0) {
            s.choose(c, s.results[s.selected]);
            return;
        }
        if (s.failed) ui.label(c, "Search could not complete");
        if (!s.failed and s.count == 0) ui.label(c, "No matching collections");
        for (s.results[0..s.count], 0..) |candidate, rank| {
            ui.key(c, entries[candidate].id);
            const row = ui.div(c).row().p(8).wFull().rounded(6)
                .bg(if (rank == s.selected) c.theme.accent.alpha(0.18) else c.theme.surface).control();
            defer row.end();
            ui.access.describe(c, row.index, .{ .label = entries[candidate].label, .selected = rank == s.selected });
            if (c.interact(row.index, .{ .focusable = true }).clicked) s.choose(c, candidate);
            ui.label(c, entries[candidate].label);
        }
    }
};

fn verify(s: *Picker) !void {
    var tester: ui.Tester = undefined;
    try tester.init(s.allocator, .init(s, Picker.view), .{ .width = 360, .height = 440 });
    defer tester.deinit();
    try tester.clickText("Choose collection");
    tester.textOps(&.{.{ .set_marked = .{ .text = "に", .sel_start = 3, .sel_len = 0 } }});
    tester.textOps(&.{.{ .insert = "日本" }});
    tester.settle(3);
    try std.testing.expectEqualStrings("日本", s.query.text());
    try std.testing.expectEqual(@as(usize, 1), s.count);
    var tree: std.ArrayList(ui.access.Element) = .empty;
    var arena = std.heap.ArenaAllocator.init(s.allocator);
    defer arena.deinit();
    try ui.access.tree(&tester.ctx, arena.allocator(), &tree);
    for (tree.items) |item| {
        if (item.role == .button and std.mem.eql(u8, item.label, "日本語の資料")) break;
    } else return error.MissingAccessibleResult;
    tester.key(.enter);
    tester.settle(3);
    try std.testing.expectEqual(@as(?u32, 3), s.chosen);
    try std.testing.expectEqual(s.trigger, tester.ctx.focus);
    try tester.clickText("Choose collection");
    tester.key(.escape);
    tester.settle(3);
    try std.testing.expect(!s.open);
    try std.testing.expectEqual(s.trigger, tester.ctx.focus);
}

pub fn main(init: std.process.Init) !void {
    const index = try search.Index.create(init.gpa, &entries, .{});
    defer index.release();
    var picker = Picker{ .allocator = init.gpa, .index = index, .io = init.io };
    defer picker.file_name.deinit();
    defer picker.file_preview.deinit();
    defer picker.query.deinit();
    if (comptime browser) {
        _ = nanoui.web.registerBundledFonts();
        _ = try nanoui.web.mount(.init(&picker, Picker.view), .{});
        nanoui.web.run();
    } else {
        const args = try init.minimal.args.toSlice(init.arena.allocator());
        if (args.len == 2 and std.mem.eql(u8, args[1], "--verify")) return verify(&picker);
        const app = try nanoui.App.create(init, .{ .name = "Collection Picker" });
        defer app.destroy();
        picker.window = try app.newWindow(.{
            .title = "Collection Picker",
            .width = 520,
            .height = 460,
            .content = .{ .view = .init(&picker, Picker.view) },
            .on_close = .{ .ctx = &picker, .func = Picker.closed },
        });
        try app.run();
    }
}
