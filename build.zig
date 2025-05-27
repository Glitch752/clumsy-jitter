const std = @import("std");
const Build = std.Build;
const Step = std.Build.Step;
const debug = std.debug;
const Allocator = std.mem.Allocator;
const CrossTarget = std.zig.CrossTarget;

const ClumsyArch = enum { x86, x64 };
const ClumsyConf = enum { Debug, Release, Ship };
const ClumsyWinDivertSign = enum { A, B, C };

pub fn build(b: *std.Build) void {
    const arch = b.option(ClumsyArch, "arch", "x86, x64") orelse .x64;
    const conf = b.option(ClumsyConf, "conf", "Debug, Release") orelse .Debug;
    const windivert_sign = b.option(ClumsyWinDivertSign, "sign", "A, B, C") orelse .A;
    const windows_kit_bin_root = b.option([]const u8, "windows_kit_bin_root", "Windows SDK Bin root") orelse "C:/Program Files (x86)/Windows Kits/10/bin/10.0.22000.0";

    const arch_tag = @tagName(arch);
    const conf_tag = @tagName(conf);
    const sign_tag = @tagName(windivert_sign);
    const windivert_dir = b.fmt("WinDivert-2.2.0-{s}", .{sign_tag});

    debug.print("- arch: {s}, conf: {s}, sign: {s}\n", .{ @tagName(arch), @tagName(conf), @tagName(windivert_sign) });
    debug.print("- windows_kit_bin_root: {s}\n", .{windows_kit_bin_root});
    _ = std.fs.realpathAlloc(b.allocator, windows_kit_bin_root) catch @panic("windows_kit_bin_root not found");

    const prefix = b.fmt("{s}_{s}_{s}", .{ arch_tag, conf_tag, sign_tag });
    b.exe_dir = b.fmt("{s}/{s}", .{ b.install_path, prefix });

    debug.print("- out: {s}\n", .{b.exe_dir});

    const tmp_path = b.makeTempPath();

    b.installFile(b.fmt("external/{s}/{s}/WinDivert.dll", .{ windivert_dir, arch_tag }), b.fmt("{s}/WinDivert.dll", .{prefix}));
    switch (arch) {
        .x64 => b.installFile(b.fmt("external/{s}/{s}/WinDivert64.sys", .{ windivert_dir, arch_tag }), b.fmt("{s}/WinDivert64.sys", .{prefix})),
        .x86 => b.installFile(b.fmt("external/{s}/{s}/WinDivert32.sys", .{ windivert_dir, arch_tag }), b.fmt("{s}/WinDivert32.sys", .{prefix})),
    }

    b.installFile("etc/config.txt", b.fmt("{s}/config.txt", .{prefix}));
    if (conf == .Ship)
        b.installFile("LICENSE", b.fmt("{s}/License.txt", .{prefix}));

    const res_obj_path = b.fmt("{s}/clumsy_res.obj", .{tmp_path});

    const rc_exe = b.findProgram(&.{
        "rc",
    }, &.{
        b.pathJoin(&.{ windows_kit_bin_root, @tagName(arch) }),
    }) catch @panic("unable to find `rc.exe`, check your windows_kit_bin_root");

    const archFlag = switch (arch) {
        .x86 => "X86",
        .x64 => "X64",
    };
    const cmd = b.addSystemCommand(&.{
        rc_exe,
        "/nologo",
        "/d",
        "NDEBUG",
        "/d",
        archFlag,
        "/r",
        "/fo",
        res_obj_path,
        "etc/clumsy.rc",
    });

    const exe = b.addExecutable(.{
        .name = "clumsy",
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });

    switch (conf) {
        .Debug => {
            exe.subsystem = .Console;
        },
        .Release => {
            exe.subsystem = .Windows;
        },
        .Ship => {
            exe.subsystem = .Windows;
        },
    }

    exe.linkLibC();

    exe.step.dependOn(&cmd.step);
    exe.addObjectFile(.{ .cwd_relative = res_obj_path });
    exe.addCSourceFile(.{ .file = b.path("src/bandwidth.c"), .flags = &.{""} });
    exe.addCSourceFile(.{ .file = b.path("src/divert.c"), .flags = &.{""} });
    exe.addCSourceFile(.{ .file = b.path("src/drop.c"), .flags = &.{""} });
    exe.addCSourceFile(.{ .file = b.path("src/duplicate.c"), .flags = &.{""} });
    exe.addCSourceFile(.{ .file = b.path("src/elevate.c"), .flags = &.{""} });
    exe.addCSourceFile(.{ .file = b.path("src/lag.c"), .flags = &.{""} });
    exe.addCSourceFile(.{ .file = b.path("src/main.c"), .flags = &.{""} });
    exe.addCSourceFile(.{ .file = b.path("src/ood.c"), .flags = &.{""} });
    exe.addCSourceFile(.{ .file = b.path("src/packet.c"), .flags = &.{""} });
    exe.addCSourceFile(.{ .file = b.path("src/reset.c"), .flags = &.{""} });
    exe.addCSourceFile(.{ .file = b.path("src/tamper.c"), .flags = &.{""} });
    exe.addCSourceFile(.{ .file = b.path("src/throttle.c"), .flags = &.{""} });
    exe.addCSourceFile(.{ .file = b.path("src/utils.c"), .flags = &.{""} });
    exe.addCSourceFile(.{ .file = b.path("src/utils.c"), .flags = &.{""} });

    if (arch == .x86)
        exe.addCSourceFile(.{ .file = b.path("etc/chkstk.s"), .flags = &.{""} });

    exe.addIncludePath(b.path(b.fmt("external/{s}/include", .{windivert_dir})));

    const iupLib = switch (arch) {
        // .x64 => "external/iup-3.30_Win64_mingw6_lib",
        // .x86 => "external/iup-3.30_Win32_mingw6_lib",
        // Instead of statically linking IUP, we will use the dynamic library
        .x64 => "external/iup-3.30_Win64_dll16_lib",
        .x86 => "external/iup-3.30_Win32_dll16_lib",
    };

    exe.addIncludePath(b.path(b.pathJoin(&.{ iupLib, "include" })));
    // exe.addCSourceFile(.{ .file = b.path(b.pathJoin(&.{ iupLib, "libiup.a" })), .flags = &.{""} });
    exe.addLibraryPath(b.path(iupLib));
    exe.linkSystemLibrary("iup");
    // Hack: Copy iup.dll to the output directory
    b.installFile(b.pathJoin(&.{ iupLib, "iup.dll" }), b.fmt("{s}/iup.dll", .{prefix}));

    exe.addLibraryPath(b.path(b.fmt("external/{s}/{s}", .{ windivert_dir, arch_tag })));
    exe.linkSystemLibrary("WinDivert");
    exe.linkSystemLibrary("comctl32");
    exe.linkSystemLibrary("Winmm");
    exe.linkSystemLibrary("ws2_32");
    exe.linkSystemLibrary("kernel32");
    exe.linkSystemLibrary("gdi32");
    exe.linkSystemLibrary("comdlg32");
    exe.linkSystemLibrary("uuid");
    exe.linkSystemLibrary("ole32");

    const exe_install_step = b.addInstallArtifact(exe, .{});
    if (conf == .Ship) {} else {
        b.getInstallStep().dependOn(&exe_install_step.step);
    }

    const clean_all = b.step("clean", "purge zig-cache and zig-out");
    clean_all.dependOn(&b.addRemoveDirTree(b.install_path).step);
    //  TODO can't clean cache atm since build.exe is in it
    // clean_all.dependOn(&b.addRemoveDirTree("zig-cache").step);
}
