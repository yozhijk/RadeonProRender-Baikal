#pragma once

#include "output.h"

#ifdef __APPLE__
#include <OpenCL/OpenCL.h>
#include <OpenGL/OpenGL.h>
#elif WIN32
#define NOMINMAX
#include <Windows.h>
#include "GL/glew.h"
#else
#include <CL/cl.h>
#include <GL/glew.h>
#include <GL/glx.h>
#endif

#ifdef DEBUG
#define CHECK_GL_ERROR {auto err = glGetError(); assert(err == GL_NO_ERROR);}
#else
#define CHECK_GL_ERROR
#endif

#include <cassert>

namespace Baikal
{

    class GlOutput : public Output
    {
    public:
        GlOutput(std::uint32_t w, std::uint32_t h);
        ~GlOutput();

        void GetData(RadeonRays::float3* data) const;

        void Clear(RadeonRays::float3 const& val);

        GLuint GetGlFramebuffer() const;

    private:
        GLuint m_frame_buffer;
        GLuint m_depth_buffer;
        GLuint m_color_buffer;

        std::uint32_t m_width;
        std::uint32_t m_height;
    };

    inline GlOutput::GlOutput(std::uint32_t w, std::uint32_t h)
        : Output(w, h)
        , m_width(w)
        , m_height(h)
    {
        glGenFramebuffers(1, &m_frame_buffer); CHECK_GL_ERROR;
        glBindFramebuffer(GL_FRAMEBUFFER, m_frame_buffer); CHECK_GL_ERROR;

        glGenRenderbuffers(1, &m_color_buffer); CHECK_GL_ERROR;
        glBindRenderbuffer(GL_RENDERBUFFER, m_color_buffer); CHECK_GL_ERROR;
        glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA16F, w, h); CHECK_GL_ERROR;
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, m_color_buffer); CHECK_GL_ERROR;

        glGenRenderbuffers(1, &m_depth_buffer); CHECK_GL_ERROR;
        glBindRenderbuffer(GL_RENDERBUFFER, m_depth_buffer); CHECK_GL_ERROR;
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT, w, h); CHECK_GL_ERROR;
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, m_depth_buffer); CHECK_GL_ERROR;

        glBindFramebuffer(GL_FRAMEBUFFER, 0); CHECK_GL_ERROR;
        glBindRenderbuffer(GL_RENDERBUFFER, 0); CHECK_GL_ERROR;
    }

    inline GlOutput::~GlOutput()
    {
        glDeleteRenderbuffers(1, &m_color_buffer);
        glDeleteRenderbuffers(1, &m_depth_buffer);
        glDeleteFramebuffers(1, &m_frame_buffer);
    }

    inline void GlOutput::GetData(RadeonRays::float3* data) const
    {
    }

    inline void GlOutput::Clear(RadeonRays::float3 const& val)
    {
        glClearColor(val.x, val.y, val.z, 1.f); CHECK_GL_ERROR;
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT); CHECK_GL_ERROR;
    }

    inline GLuint GlOutput::GetGlFramebuffer() const
    {
        return m_frame_buffer;
    }
}