#include "scene_binary_io.h"
#include "SceneGraph/scene1.h"
#include "SceneGraph/iterator.h"
#include "SceneGraph/shape.h"
#include "SceneGraph/material.h"
#include "SceneGraph/light.h"
#include "SceneGraph/texture.h"
#include "SceneGraph/IO/image_io.h"
#include <fstream>

namespace Baikal
{
    std::unique_ptr<SceneIo> SceneIo::CreateSceneIoBinary()
    {
        return std::unique_ptr<SceneIo>(new SceneBinaryIo());
    }

    std::unique_ptr<Scene1> SceneBinaryIo::LoadScene(std::string const& filename, std::string const& basepath) const
    {
        Scene1* scene = new Scene1;

        std::string full_path = filename;

        std::ifstream in(full_path, std::ios::binary | std::ios::in);

        if (!in)
        {
            throw std::runtime_error("Cannot open file for reading");
        }

        std::uint32_t num_meshes = 0;
        in.read((char*)&num_meshes, sizeof(std::uint32_t));

        auto material = new SingleBxdf(SingleBxdf::BxdfType::kLambert);

        for (auto i = 0U; i < 15000; ++i)
        {
            auto mesh = new Mesh();

            std::uint32_t num_indices = 0;
            in.read((char*)&num_indices, sizeof(std::uint32_t));

            std::uint32_t num_vertices = 0;
            in.read((char*)&num_vertices, sizeof(std::uint32_t));


            std::uint32_t num_normals = 0;
            in.read((char*)&num_normals, sizeof(std::uint32_t));


            std::uint32_t num_uvs = 0;
            in.read((char*)&num_uvs, sizeof(std::uint32_t));

            {
                std::vector<std::uint32_t> indices(num_indices);
                in.read((char*)&indices[0], num_indices * sizeof(std::uint32_t));

                mesh->SetIndices(&indices[0], num_indices);
            }

            {
                std::vector<RadeonRays::float3> vertices(num_vertices);
                in.read((char*)&vertices[0], num_vertices * sizeof(RadeonRays::float3));

                mesh->SetVertices(&vertices[0], num_vertices);
            }

            {
                std::vector<RadeonRays::float3> normals(num_normals);
                in.read((char*)&normals[0], num_normals * sizeof(RadeonRays::float3));

                mesh->SetNormals(&normals[0], num_normals);
            }

            {
                std::vector<RadeonRays::float2> uvs(num_uvs);
                in.read((char*)&uvs[0], num_uvs * sizeof(RadeonRays::float2));

                mesh->SetUVs(&uvs[0], num_uvs);
            }

            mesh->SetMaterial(material);
            scene->AttachShape(mesh);
            scene->AttachAutoreleaseObject(mesh);
        }

        auto image_io(ImageIo::CreateImageIo());

        Texture* ibl_texture = image_io->LoadImage("../Resources/Textures/sky.hdr");
        scene->AttachAutoreleaseObject(ibl_texture);

        ImageBasedLight* ibl = new ImageBasedLight();
        ibl->SetTexture(ibl_texture);
        ibl->SetMultiplier(1.f);
        scene->AttachAutoreleaseObject(ibl);

        // TODO: temporary code to add directional light
        DirectionalLight* light = new DirectionalLight();
        light->SetDirection(RadeonRays::normalize(RadeonRays::float3(-1.1f, -0.6f, -0.4f)));
        light->SetEmittedRadiance(7.f * RadeonRays::float3(1.f, 0.95f, 0.92f));
        scene->AttachAutoreleaseObject(light);

        DirectionalLight* light1 = new DirectionalLight();
        light1->SetDirection(RadeonRays::float3(0.3f, -1.f, -0.5f));
        light1->SetEmittedRadiance(RadeonRays::float3(1.f, 0.8f, 0.65f));
        scene->AttachAutoreleaseObject(light1);

        scene->AttachLight(light);
        //scene->AttachLight(light1);
        scene->AttachLight(ibl);

        return std::unique_ptr<Scene1>(scene);
    }

    void SceneBinaryIo::SaveScene(Scene1 const& scene, std::string const& filename, std::string const& basepath) const
    {
        std::string full_path = filename;

        std::ofstream out(full_path, std::ios::binary | std::ios::out);

        if (!out)
        {
            throw std::runtime_error("Cannot open file for writing");
        }

        auto num_shapes = (std::uint32_t)scene.GetNumShapes();
        out.write((char*)&num_shapes, sizeof(std::uint32_t));

        auto shape_iter = scene.CreateShapeIterator();

        for (; shape_iter->IsValid(); shape_iter->Next())
        {
            auto mesh = shape_iter->ItemAs<Mesh const>();
            auto num_indices = (std::uint32_t)mesh->GetNumIndices();
            out.write((char*)&num_indices, sizeof(std::uint32_t));

            auto num_vertices = (std::uint32_t)mesh->GetNumVertices();
            out.write((char*)&num_vertices, sizeof(std::uint32_t));

            auto num_normals = (std::uint32_t)mesh->GetNumNormals();
            out.write((char*)&num_normals, sizeof(std::uint32_t));

            auto num_uvs = (std::uint32_t)mesh->GetNumUVs();
            out.write((char*)&num_uvs, sizeof(std::uint32_t));

            out.write((char const*)mesh->GetIndices(), mesh->GetNumIndices() * sizeof(std::uint32_t));
            out.write((char const*)mesh->GetVertices(), mesh->GetNumVertices() * sizeof(RadeonRays::float3));
            out.write((char const*)mesh->GetNormals(), mesh->GetNumNormals() * sizeof(RadeonRays::float3));
            out.write((char const*)mesh->GetUVs(), mesh->GetNumUVs() * sizeof(RadeonRays::float2));
        }
    }
}