// dear imgui: Renderer Backend for SDL_GPU
// This needs to be used along with the SDL3 Platform Backend

// Implemented features:
//  [X] Renderer: User texture binding. Use simply cast a reference to your SDL_GPUTextureSamplerBinding to ImTextureID.
//  [X] Renderer: Large meshes support (64k+ vertices) with 16-bit indices.
// Missing features:
//  [ ] Renderer: Multi-viewport support (multiple windows).

// The aim of imgui_impl_sdlgpu3.h/.cpp is to be usable in your engine without any modification.
// IF YOU FEEL YOU NEED TO MAKE ANY CHANGE TO THIS CODE, please share them and your feedback at https://github.com/ocornut/imgui/

// You can use unmodified imgui_impl_* files in your project. See examples/ folder for examples of using this.
// Prefer including the entire imgui/ repository into your project (either as a copy or as a submodule), and only build the backends you need.
// Learn about Dear ImGui:
// - FAQ                  https://dearimgui.com/faq
// - Getting Started      https://dearimgui.com/getting-started
// - Documentation        https://dearimgui.com/docs (same as your local docs/ folder).
// - Introduction, links and more at the top of imgui.cpp

// Important note to the reader who wish to integrate imgui_impl_sdlgpu3.cpp/.h in their own engine/app.
// - Unline other backends, the user must call the function Imgui_ImplSDLGPU_PrepareDrawData BEFORE issuing a SDL_GPURenderPass containing ImGui_ImplSDLGPU_RenderDrawData.
//   Calling the function is MANDATORY, otherwise the ImGui will not upload neither the vertex nor the index buffer for the GPU. See imgui_impl_sdlgpu3.cpp for more info.

#pragma once
// #include "imgui.h"      // IMGUI_IMPL_API
#ifndef IMGUI_DISABLE
#define IMGUI_IMPL_API
#include <SDL3/SDL_gpu.h>

struct ImDrawData;

struct SDL_Window;
struct SDL_Renderer;
union SDL_Event;


IMGUI_IMPL_API bool     ImGui_ImplSDL3_InitForOpenGL(SDL_Window* window, void* sdl_gl_context);
IMGUI_IMPL_API bool     ImGui_ImplSDL3_InitForVulkan(SDL_Window* window);
IMGUI_IMPL_API bool     ImGui_ImplSDL3_InitForD3D(SDL_Window* window);
IMGUI_IMPL_API bool     ImGui_ImplSDL3_InitForMetal(SDL_Window* window);
IMGUI_IMPL_API bool     ImGui_ImplSDL3_InitForSDLRenderer(SDL_Window* window, SDL_Renderer* renderer);
IMGUI_IMPL_API bool     ImGui_ImplSDL3_InitForSDLGPU(SDL_Window* window);
IMGUI_IMPL_API bool     ImGui_ImplSDL3_InitForOther(SDL_Window* window);
IMGUI_IMPL_API void     ImGui_ImplSDL3_Shutdown();
IMGUI_IMPL_API void     ImGui_ImplSDL3_NewFrame();
IMGUI_IMPL_API bool     ImGui_ImplSDL3_ProcessEvent(const SDL_Event* event);

// Initialization data, for ImGui_ImplSDLGPU_Init()
// - Remember to set ColorTargetFormat to the correct format. If you're rendering to the swapchain, call SDL_GetGPUSwapchainTextureFormat to query the right value
typedef struct
{
    SDL_GPUDevice*       Device;
    SDL_GPUTextureFormat ColorTargetFormat;
    SDL_GPUSampleCount   MSAASamples;
} ImGui_ImplSDLGPU3_InitInfo;

// Follow "Getting Started" link and check examples/ folder to learn about using backends!
IMGUI_IMPL_API bool     ImGui_ImplSDLGPU3_Init(ImGui_ImplSDLGPU3_InitInfo* info);
IMGUI_IMPL_API void     ImGui_ImplSDLGPU3_Shutdown();
IMGUI_IMPL_API void     ImGui_ImplSDLGPU3_NewFrame();
IMGUI_IMPL_API void     Imgui_ImplSDLGPU3_PrepareDrawData(ImDrawData* draw_data, SDL_GPUCommandBuffer* command_buffer);
IMGUI_IMPL_API void     ImGui_ImplSDLGPU3_RenderDrawData(ImDrawData* draw_data, SDL_GPUCommandBuffer* command_buffer, SDL_GPURenderPass* render_pass, SDL_GPUGraphicsPipeline* pipeline);

IMGUI_IMPL_API void     ImGui_ImplSDLGPU3_CreateDeviceObjects();
IMGUI_IMPL_API void     ImGui_ImplSDLGPU3_DestroyDeviceObjects();
IMGUI_IMPL_API void     ImGui_ImplSDLGPU3_CreateFontsTexture();
IMGUI_IMPL_API void     ImGui_ImplSDLGPU3_DestroyFontsTexture();

#endif // #ifndef IMGUI_DISABLE
