pub usingnamespace @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3_image/SDL_image.h");

    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "1");
    @cInclude("cimgui.h");
    @cInclude("tongue.h");

    // @cInclude("SDL3/SDL_vulkan.h");

    // @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "1");
    // @cDefine("CIMGUI_USE_SDL3", "1");
    // // @cDefine("CIMGUI_USE_VULKAN", "1");
    // @cInclude("cimgui.h");
    // @cInclude("cimgui_impl.h");
});
