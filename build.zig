const std = @import("std");

fn create_exe(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "mlam",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.linkLibCpp();
    exe.linkSystemLibrary("SDL3");

    const imgui_lib = b.addStaticLibrary(.{
        .name = "imguilib",
        .target = target,
        .optimize = optimize,
    });

    const imgui = b.dependency("imgui", .{});
    const cimgui = b.dependency("cimgui", .{});

    exe.addCSourceFile(.{ .file = imgui.path("imgui.cpp") });
    exe.addCSourceFile(.{ .file = cimgui.path("cimgui.cpp") });

    // package imgui into a static library, so cimgui can find it without having to clone
    imgui_lib.addIncludePath(imgui.path(""));
    exe.addIncludePath(imgui.path(""));
    imgui_lib.root_module.addCMacro("IMGUI_IMPL_API", "extern \"C\"");
    imgui_lib.addCSourceFile(.{ .file = imgui.path("imgui_demo.cpp") });
    imgui_lib.addCSourceFile(.{ .file = imgui.path("imgui_draw.cpp") });
    imgui_lib.addCSourceFile(.{ .file = imgui.path("imgui_widgets.cpp") });
    imgui_lib.addCSourceFile(.{ .file = imgui.path("imgui_tables.cpp") });
    imgui_lib.addCSourceFile(.{ .file = imgui.path("backends/imgui_impl_sdlgpu3.cpp") });
    imgui_lib.addCSourceFile(.{ .file = imgui.path("backends/imgui_impl_sdl3.cpp") });
    imgui_lib.installHeader(imgui.path("imgui.h"), "imgui/imgui.h");
    imgui_lib.installHeader(imgui.path("imgui_internal.h"), "imgui/imgui_internal.h");
    imgui_lib.linkLibC();
    imgui_lib.linkLibCpp();
    exe.addCSourceFile(.{ .file = cimgui.path("cimgui_impl.cpp") });
    exe.linkLibrary(imgui_lib);
    exe.addIncludePath(cimgui.path(""));
    exe.addIncludePath(b.path("src/include/"));

    return exe;
}

fn checkIsShaderFile(file: std.fs.Dir.Walker.Entry) bool {
    const allowedShaderExtensions: (*const [3]*const [5:0]u8) = &.{
        ".vert",
        ".frag",
        ".comp",
    };
    if (file.kind != .file) {
        return false;
    }
    for (allowedShaderExtensions) |ext| {
        if (std.mem.endsWith(u8, file.basename, ext)) {
            return true;
        }
    }
    return false;
}

fn compileShaders(b: *std.Build) !void {
    const shaderPath = "src/shaders/";
    const shaderBuildPath = "build/shaders/";

    if (b.build_root.path == null) {
        return error.InvalidBuildRoot;
    }
    const cwd = try std.fs.openDirAbsolute(b.build_root.path.?, .{});

    try cwd.makePath(shaderBuildPath);

    const shaderDir = try cwd.openDir(shaderPath, .{ .iterate = true, .access_sub_paths = true, .no_follow = false });

    var walker = try shaderDir.walk(b.allocator);
    defer walker.deinit();

    while (try walker.next()) |shader| {
        if (!checkIsShaderFile(shader)) {
            continue;
        }

        const path = try std.mem.join(b.allocator, "", &.{ shaderPath, shader.basename });
        try compileShader(path, shaderBuildPath, shader.basename, b.allocator);
    }
}

const Shader_HarshCompilationReq = true;
fn compileShader(path: []const u8, destination_path: []const u8, shader_name: []const u8, alloc: std.mem.Allocator) !void {
    const compile = try std.mem.join(alloc, "", &.{ destination_path, shader_name, ".spv" });
    defer alloc.free(compile);

    // parse shader type
    // get file extension
    var last_dot_index = shader_name.len - 1;
    while (last_dot_index >= 0) : (last_dot_index -= 1) {
        if (shader_name[last_dot_index] == '.') {
            break;
        }
    }
    if (last_dot_index < 0) {
        std.log.debug("invalid shader name {s}", .{shader_name});
        return;
    }
    const shader_extension = shader_name[last_dot_index..];
    var shader_type: ?[]const u8 = null;
    if (std.mem.eql(u8, shader_extension, ".vert")) {
        shader_type = std.fmt.allocPrint(alloc, "vs_5_1", .{}) catch unreachable;
    } else if (std.mem.eql(u8, shader_extension, ".frag")) {
        shader_type = std.fmt.allocPrint(alloc, "ps_5_1", .{}) catch unreachable;
    }

    if (shader_type == null) {
        std.log.debug("invalid shader ext {s}", .{shader_name});
        return;
    }

    var dxc = std.process.Child.init(&.{ "dxc", path, "-spirv", "-T", shader_type.?, "-Fo", compile }, alloc);
    const exit_info = try dxc.spawnAndWait();
    if (exit_info.Exited != 0 and Shader_HarshCompilationReq) {
        // std.log.err("glslang failed to compile shader: {s}", .{path});
        return error.FailedShaderCompilation;
    }
}

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    compileShaders(b) catch @panic("rip shader :(");
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.
    const exe = create_exe(b, target, optimize);
    const exe_check = create_exe(b, target, optimize);
    const check = b.step("check", "Check if foo compiles");
    check.dependOn(&exe_check.step);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
