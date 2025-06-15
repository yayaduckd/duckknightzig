const c = @import("cmix.zig");
const std = @import("std");
const mk = @import("mkmix.zig");

pub const SHADER_PATH = "build/shaders";
pub const TEXTURE_PATH = "textures";

pub const PositionTextureVertex = struct {
    x: f32,
    y: f32,
    z: f32,

    u: f32,
    v: f32,
};

pub const PositionTextureColorVertex = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    blep: f32 = 1,

    u: f32 = 0,
    v: f32 = 0,

    r: f32 = 0,
    g: f32 = 0,
    b: f32 = 0,
    a: f32 = 0,
};

pub const FragMultiplyUniform = extern struct {
    r: f32 = 0,
    g: f32 = 0,
    b: f32 = 0,
    a: f32 = 0,
};

pub fn sdlr(success: bool) !void {
    if (!success) {
        const err_str_ptr = c.SDL_GetError();
        std.log.err("sdl error: {s}", .{err_str_ptr});
        return error.SDLBorken;
    }
}

pub fn sdlv(value: anytype) !@TypeOf(value.?) {
    if (value == null) {
        const err_str_ptr = c.SDL_GetError();
        if (err_str_ptr) |raw_err_str| {
            std.log.err("SDL Error: {s}", .{std.mem.sliceTo(raw_err_str, 0)});
        } else {
            std.log.err("(no sdl error message available)", .{});
        }
        return error.MkSDLVNullError;
    }
    return value.?;
}

pub fn fatal_sdl_error(comptime msg: []const u8) !void {
    const err_str_ptr = c.SDL_GetError();
    if (err_str_ptr) |raw_err_str| {
        std.log.err("{s} - {s}", .{ msg, std.mem.sliceTo(raw_err_str, 0) });
    } else {
        std.log.err("{s} - (no sdl error message available)", .{msg});
    }
    return error.SDLBorken;
}

const ShaderType = enum {
    Vertex,
    Fragment,
    Compute,
};

pub fn load_shader_bytes(
    device: *c.SDL_GPUDevice,
    stage: c.SDL_GPUShaderStage,
    bytes: []const u8,
    sampler_count: u32,
    uniform_buffer_count: u32,
    storage_buffer_count: u32,
    storage_texture_count: u32,
) !*c.SDL_GPUShader {
    const shader_info: c.SDL_GPUShaderCreateInfo = .{
        .code = @ptrCast(bytes),
        .code_size = bytes.len,
        .entrypoint = "main",
        .format = c.SDL_GPU_SHADERFORMAT_SPIRV,
        .stage = stage,
        .num_samplers = sampler_count,
        .num_uniform_buffers = uniform_buffer_count,
        .num_storage_buffers = storage_buffer_count,
        .num_storage_textures = storage_texture_count,
    };
    const shaderOrNull = c.SDL_CreateGPUShader(device, &shader_info);
    if (shaderOrNull) |shader| {
        // c.SDL_free(code);
        return shader;
    }
    std.log.debug("failed to create shader", .{});
    // c.SDL_free(code);
    return error.MkShaderCreationFailed;
}

pub fn load_shader(
    device: *c.SDL_GPUDevice,
    filename: []const u8,
    sampler_count: u32,
    uniform_buffer_count: u32,
    storage_buffer_count: u32,
    storage_texture_count: u32,
) !*c.SDL_GPUShader {
    const stage: c.SDL_GPUShaderStage = switch (determine_shader_type(filename)) {
        .Vertex => c.SDL_GPU_SHADERSTAGE_VERTEX,
        .Fragment => c.SDL_GPU_SHADERSTAGE_FRAGMENT,
        .Compute => @panic("not supported"),
    };

    var buf: [512]u8 = undefined;
    const full_filepath = std.fmt.bufPrintZ(&buf, "{s}/{s}", .{ mk.SHADER_PATH, filename }) catch {
        return error.MkFormatFilepathError;
    };

    var code_size: usize = 0;
    const code = c.SDL_LoadFile(full_filepath, &code_size);
    defer c.SDL_free(code);

    var bytes: []u8 = undefined;
    bytes.len = code_size;
    bytes.ptr = @ptrCast(code);

    return load_shader_bytes(device, stage, bytes, sampler_count, uniform_buffer_count, storage_buffer_count, storage_texture_count);
}

pub fn determine_shader_type(filename: []const u8) ShaderType {
    // parse shader type
    // get file extension
    var last_dot_index = filename.len - 1;
    var second_last_dot_index = filename.len - 1;
    while (last_dot_index >= 0) : (last_dot_index -= 1) {
        if (filename[last_dot_index] == '.') {
            break;
        }
    }
    second_last_dot_index = last_dot_index - 1;
    while (second_last_dot_index >= 0) : (second_last_dot_index -= 1) {
        if (filename[second_last_dot_index] == '.') {
            break;
        }
    }
    if (last_dot_index < 0) {
        std.log.panic("invalid shader name {s}", .{filename});
        return;
    }
    const shader_extension = filename[second_last_dot_index..last_dot_index];
    if (std.mem.eql(u8, shader_extension, ".vert")) {
        return ShaderType.Vertex;
    } else if (std.mem.eql(u8, shader_extension, ".frag")) {
        return ShaderType.Fragment;
    } else if (std.mem.eql(u8, shader_extension, ".comp")) {
        return ShaderType.Compute;
    } else {
        std.debug.panic("Invalid shader type {s}", .{shader_extension});
    }
}

pub fn load_image(filename: []const u8, desired_channels: u8) !*c.SDL_Surface {
    var path_buf: [256]u8 = undefined;
    var format: c.SDL_PixelFormat = undefined;

    const full_path = try std.fmt.bufPrintZ(&path_buf, "{s}/{s}", .{ TEXTURE_PATH, filename });

    var result: ?*c.SDL_Surface = c.IMG_Load(full_path);

    if (result == null) {
        return error.MkCouldntLoadBMP;
    }

    if (desired_channels == 4) {
        format = c.SDL_PIXELFORMAT_ABGR8888;
    } else {
        // c.SDL_assert(!"Unexpected desiredChannels");
        c.SDL_DestroySurface(result);
        @panic("squeeb");
    }
    if (result.?.format != format) {
        const next = c.SDL_ConvertSurface(result, format);
        c.SDL_DestroySurface(result);
        result = next;
    }

    return result.?;
}

pub var frame_print_buffer: [8192]u8 = undefined;
var frame_print_offset: usize = 0;
pub fn frame_print(comptime fmt: []const u8, args: anytype) void {
    const slice = std.fmt.bufPrint(frame_print_buffer[frame_print_offset..], fmt, args) catch @panic("out of frame print space");
    frame_print_offset += slice.len;
}

pub fn reset_frame_print_buffer() void {
    frame_print_offset = 0;
    mk.frame_print_buffer = std.mem.zeroes([8192]u8);
}
