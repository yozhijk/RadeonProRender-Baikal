#include "gl_scene_controller.h"
#include "SceneGraph/material.h"
#include "SceneGraph/iterator.h"
#include "SceneGraph/texture.h"
#include <cassert>

#include <iostream>

#ifdef DEBUG
#define CHECK_GL_ERROR {auto err = glGetError(); assert(err == GL_NO_ERROR);}
#else
#define CHECK_GL_ERROR
#endif

namespace Baikal
{
    GlSceneController::GlSceneController()
    {
    }

    GlSceneController::~GlSceneController()
    {
    }

    void GlSceneController::UpdateCamera(Scene1 const& scene, Collector& mat_collector, Collector& tex_collector, GlScene& out) const
    {
        auto camera = reinterpret_cast<PerspectiveCamera const*>(scene.GetCamera());
        out.camera = camera;
    }

    void GlSceneController::UpdateShapes(Scene1 const& scene, Collector& mat_collector, Collector& tex_collector, GlScene& out) const
    {
        std::cout << "Shape update started\n";
        // Delete all meshes previously created
        if (out.vertex_buffer != GL_INVALID_ENUM)
        {
            glDeleteBuffers(1, &out.index_buffer);
            glDeleteBuffers(1, &out.vertex_buffer);
        }


        std::unique_ptr<Iterator> shape_iter(scene.CreateShapeIterator());

        // Sort shapes into meshes and instances sets.
        std::set<Mesh const*> meshes;
        // Excluded meshes are meshes which are not in the scene, 
        // but are references by at least one instance.
        std::set<Mesh const*> excluded_meshes;
        std::set<Instance const*> instances;
        SplitMeshesAndInstances(shape_iter.get(), meshes, instances, excluded_meshes);

        // Calculate space required
        auto num_indices = 0;
        auto num_vertices = 0;
        for (auto& iter : meshes)
        {
            num_indices += iter->GetNumIndices();
            num_vertices += iter->GetNumVertices();
        }

        std::cout << "Total number of vertices " << num_vertices << "\n";
        std::cout << "Total number of indices " << num_indices<< "\n";

        glGenBuffers(1, &out.vertex_buffer); CHECK_GL_ERROR;
        glGenBuffers(1, &out.index_buffer); CHECK_GL_ERROR;

        glBindBuffer(GL_ARRAY_BUFFER, out.vertex_buffer); CHECK_GL_ERROR;
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, out.index_buffer); CHECK_GL_ERROR;

        glBufferData(GL_ARRAY_BUFFER,
            sizeof(GlVertex) * num_vertices,
            nullptr,
            GL_STATIC_DRAW); CHECK_GL_ERROR;

        glBufferData(GL_ELEMENT_ARRAY_BUFFER,
            sizeof(std::uint32_t) * num_indices,
            nullptr,
            GL_STATIC_DRAW); CHECK_GL_ERROR;


        GLint mask = GL_MAP_WRITE_BIT;

        
        auto num_vertices_written = 0;
        auto num_indices_written = 0;

        int k = 0;
        for (auto& iter : meshes)
        {
            std::cout << "Mesh (" << k++ << "/" << meshes.size() << ")\n";
            auto mesh = iter;

            auto vertex_ptr = mesh->GetVertices();
            auto normal_ptr = mesh->GetNormals();
            auto uv_ptr = mesh->GetUVs();
            auto idx_ptr = mesh->GetIndices();
            auto start_index = num_vertices_written;
            auto num_vertices = std::min(mesh->GetNumVertices(), mesh->GetNumNormals());
            auto num_indices = mesh->GetNumIndices();

            auto vertices = (GlVertex*)glMapBufferRange(GL_ARRAY_BUFFER, num_vertices_written * sizeof(GlVertex), 
                num_vertices * sizeof(GlVertex), mask); CHECK_GL_ERROR;
            auto indices = (std::uint32_t*)glMapBufferRange(GL_ELEMENT_ARRAY_BUFFER, num_indices_written * sizeof(std::uint32_t),
                num_indices * sizeof(std::uint32_t), mask); CHECK_GL_ERROR;

            for (auto i = 0; i < num_vertices; ++i)
            {
                vertices[i].p = vertex_ptr[i];
                vertices[i].n = normal_ptr[i];
                vertices[i].uv = uv_ptr[i];
            }

            for (auto i = 0; i < mesh->GetNumIndices(); ++i)
            {
                indices[i] = idx_ptr[i] + start_index;
            }

            num_vertices_written += num_vertices;
            num_indices_written += mesh->GetNumIndices();

            glUnmapBuffer(GL_ARRAY_BUFFER);
            glUnmapBuffer(GL_ELEMENT_ARRAY_BUFFER);
        }


        glBindBuffer(GL_ARRAY_BUFFER, 0);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);

        out.num_indices = num_indices_written;

        std::cout << "Shape update finished\n";
    }

    void GlSceneController::UpdateLights(Scene1 const& scene, Collector& mat_collector, Collector& tex_collector, GlScene& out) const
    {
        out.ibl_texture_idx = -1;
        out.ibl_multiplier = 1.f;

        std::unique_ptr<Iterator> light_iter(scene.CreateLightIterator());
        for (; light_iter->IsValid(); light_iter->Next())
        {
            auto light = light_iter->ItemAs<Light const>();
            // Find and update IBL idx
            auto ibl = dynamic_cast<ImageBasedLight const*>(light_iter->ItemAs<Light const>());
            if (ibl)
            {
                out.ibl_texture_idx = tex_collector.GetItemIndex(ibl->GetTexture());
                out.ibl_multiplier = ibl->GetMultiplier();
            }
        }
    }

    void GlSceneController::UpdateMaterials(Scene1 const& scene, Collector& mat_collector, Collector& tex_collector, GlScene& out) const
    {
        out.materials.clear();

        std::unique_ptr<Iterator> iter(mat_collector.CreateIterator());

        for (; iter->IsValid(); iter->Next())
        {
            auto material = iter->ItemAs<Material const>();

            GlMaterialData new_data;
            if (auto simple = dynamic_cast<SingleBxdf const*>(material))
            {
                if (simple->GetBxdfType() == SingleBxdf::BxdfType::kLambert)
                {
                    auto albedo_input = simple->GetInputValue("albedo");

                    if (albedo_input.type == Material::InputType::kFloat4)
                    {
                        new_data.diffuse_color = albedo_input.float_value;
                        new_data.diffuse_texture_idx = -1;
                    }
                    else
                    {
                        new_data.diffuse_texture_idx = tex_collector.GetItemIndex(albedo_input.tex_value);
                    }

                    new_data.ior = 0.f;
                }
                else
                {
                    auto albedo_input = simple->GetInputValue("albedo");

                    if (albedo_input.type == Material::InputType::kFloat4)
                    {
                        new_data.gloss_color = albedo_input.float_value;
                        new_data.gloss_texture_idx = -1;
                    }
                    else
                    {
                        new_data.gloss_texture_idx = tex_collector.GetItemIndex(albedo_input.tex_value);
                    }

                    new_data.diffuse_texture_idx = -1;

                    if (simple->GetBxdfType() == SingleBxdf::BxdfType::kMicrofacetGGX)
                    {
                        auto gloss_rougness_input = simple->GetInputValue("roughness");

                        if (gloss_rougness_input.type == Material::InputType::kFloat4)
                        {
                            new_data.gloss_roughness = gloss_rougness_input.float_value.x;
                        }
                        else
                        {
                            new_data.gloss_roughness = 0.f;
                        }
                    }
                    else
                    {
                        new_data.gloss_roughness = 0.01f;
                        new_data.diffuse_roughness = 0.f;
                    }

                    new_data.ior = 1.f;
                }
            }
            else
            {
                auto compound = dynamic_cast<MultiBxdf const*>(material);
                if (compound && compound->GetType() == MultiBxdf::Type::kFresnelBlend)
                {
                    auto top = material->GetInputValue("top_material").mat_value;
                    auto base = material->GetInputValue("base_material").mat_value;
                    auto ior = material->GetInputValue("ior").float_value;

                    auto diffuse_albedo_input = base->GetInputValue("albedo");

                    if (diffuse_albedo_input.type == Material::InputType::kFloat4)
                    {
                        new_data.diffuse_color = diffuse_albedo_input.float_value;
                        new_data.diffuse_texture_idx = -1;
                    }
                    else
                    {
                        new_data.diffuse_texture_idx = tex_collector.GetItemIndex(diffuse_albedo_input.tex_value);
                    }

                    auto gloss_albedo_input = top->GetInputValue("albedo");

                    if (gloss_albedo_input.type == Material::InputType::kFloat4)
                    {
                        new_data.gloss_color = gloss_albedo_input.float_value;
                        new_data.gloss_texture_idx = -1;
                    }
                    else
                    {
                        new_data.gloss_texture_idx = tex_collector.GetItemIndex(gloss_albedo_input.tex_value);
                    }

                    if (reinterpret_cast<SingleBxdf const*>(top)->GetBxdfType() == SingleBxdf::BxdfType::kMicrofacetGGX)
                    {
                        auto gloss_rougness_input = top->GetInputValue("roughness");

                        if (gloss_rougness_input.type == Material::InputType::kFloat4)
                        {
                            new_data.gloss_roughness = gloss_rougness_input.float_value.x;
                        }
                        else
                        {
                            new_data.gloss_roughness = 0.f;
                        }
                    }
                    else
                    {
                        new_data.gloss_roughness = 0.01f;
                        new_data.diffuse_roughness = 0.f;
                    }

                    new_data.ior = ior.x;
                    new_data.diffuse_roughness = 0.f;
                }
            }

            out.materials.push_back(new_data);
        }

        out.material_bundle.reset(mat_collector.CreateBundle());
    }

    static void Baikal2GlTextureFormat(Texture::Format format, GLenum& internal_format, GLenum& type)
    {
        switch (format)
        {
        case Texture::Format::kRgba32:
        {
            internal_format = GL_RGBA32F;
            type = GL_FLOAT;
            return;
        }
        case Texture::Format::kRgba16:
        {
            internal_format = GL_RGBA16F;
            type = GL_FLOAT;
            return;
        }
        case Texture::Format::kRgba8:
        {
            internal_format = GL_RGBA8;
            type = GL_UNSIGNED_BYTE;
            return;
        }
        }
    }

    void GlSceneController::UpdateTextures(Scene1 const& scene, Collector& mat_collector, Collector& tex_collector, GlScene& out) const
    {
        for (auto& iter : out.textures)
        {
            if (iter.texture == 0xFFFFFFFFU)
            {
                glDeleteTextures(1, &iter.texture);
            }
        }

        out.textures.clear();

        std::unique_ptr<Iterator> iter(tex_collector.CreateIterator());

        for (; iter->IsValid(); iter->Next())
        {
            GlTexureData new_data;
            auto texture = iter->ItemAs<Texture const>();
            auto size = texture->GetSize();

            glGenTextures(1, &new_data.texture);
            glBindTexture(GL_TEXTURE_2D, new_data.texture); CHECK_GL_ERROR;
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR_MIPMAP_LINEAR); CHECK_GL_ERROR;
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR); CHECK_GL_ERROR;

            GLenum format;
            GLenum type;
            Baikal2GlTextureFormat(texture->GetFormat(), format, type);
            glTexImage2D(GL_TEXTURE_2D, 0, format, size.x, size.y, 0, GL_RGBA, type, texture->GetData()); CHECK_GL_ERROR;
            glGenerateMipmap(GL_TEXTURE_2D); CHECK_GL_ERROR;
            glBindTexture(GL_TEXTURE_2D, 0); CHECK_GL_ERROR;

            out.textures.push_back(new_data);
        }

        out.texture_bundle.reset(tex_collector.CreateBundle());
    }

    Material const* GlSceneController::GetDefaultMaterial() const
    {
        return nullptr;
    }

    void GlSceneController::UpdateCurrentScene(Scene1 const& scene, GlScene& out) const
    {

    }

}