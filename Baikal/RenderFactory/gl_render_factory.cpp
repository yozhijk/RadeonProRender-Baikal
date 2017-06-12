#include "gl_render_factory.h"

#include "Renderers/rsrenderer.h"
#include "Output/gloutput.h"
#include "PostEffects/post_effect.h"

namespace Baikal
{
    GlRenderFactory::GlRenderFactory()
    {
    }

    // Create a renderer of specified type
    std::unique_ptr<Renderer> GlRenderFactory::CreateRenderer(
        RendererType type) const
    {
        switch (type)
        {
        case RendererType::kUnidirectionalPathTracer:
            return std::unique_ptr<Renderer>(new RsRenderer());
        default:
            throw std::runtime_error("Renderer not supported");
        }
    }

    // Create an output of specified type
    std::unique_ptr<Output> GlRenderFactory::CreateOutput(std::uint32_t w,
        std::uint32_t h)
        const
    {
        return std::unique_ptr<Output>(new GlOutput(w, h));
    }

    // Create post effect of specified type
    std::unique_ptr<PostEffect> GlRenderFactory::CreatePostEffect(
        PostEffectType type) const
    {
        return nullptr;
    }

    std::unique_ptr<RenderFactory> RenderFactory::CreateGlRenderFactory()
    {
        return std::unique_ptr<RenderFactory>(new GlRenderFactory());
    }
}
