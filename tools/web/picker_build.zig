//! Optional integration fixture using the sibling workspace's actual search.
const std = @import("std");

pub fn add(b: *std.Build, workspace: []const u8, native: *std.Build.Module, browser: *std.Build.Module, web_demo: *std.Build.Step) void {
    const verify = b.step("picker-check", "Run the shared collection picker offscreen");
    for ([_]*std.Build.Module{ native, browser }) |ui| {
        const target = ui.resolved_target.?;
        const wasm = target.result.os.tag == .wasi;
        if (!wasm and (target.result.abi.isAndroid() or target.result.os.tag == .ios)) continue;
        const optimize = ui.optimize.?;
        const text = b.createModule(.{
            .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ workspace, "libs/text/src/root.zig" }) },
            .target = target,
            .optimize = optimize,
            .single_threaded = wasm,
        });
        const search = b.createModule(.{
            .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ workspace, "libs/search/src/root.zig" }) },
            .target = target,
            .optimize = optimize,
            .single_threaded = wasm,
            .imports = &.{.{ .name = "shared_text", .module = text }},
        });
        const exe = b.addExecutable(.{
            .name = "collection-picker",
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/collection-picker/main.zig"),
                .target = target,
                .optimize = optimize,
                .single_threaded = wasm,
                .imports = &.{ .{ .name = "nanoui", .module = ui }, .{ .name = "shared_search", .module = search } },
            }),
        });
        if (wasm) {
            web_demo.dependOn(@import("build.zig").install(b, exe, b.path(".")));
        } else {
            b.installArtifact(exe);
            const run = b.addRunArtifact(exe);
            run.addArg("--verify");
            verify.dependOn(&run.step);
        }
    }
}
