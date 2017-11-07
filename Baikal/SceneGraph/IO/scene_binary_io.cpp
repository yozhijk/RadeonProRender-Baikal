#include "scene_binary_io.h"
#include "SceneGraph/scene1.h"
#include "SceneGraph/iterator.h"
#include "SceneGraph/shape.h"
#include "SceneGraph/material.h"
#include "SceneGraph/light.h"
#include "SceneGraph/texture.h"
#include "SceneGraph/IO/image_io.h"
#include "math/mathutils.h"
#include "Utils/log.h"

#include <fstream>
#include <unordered_map>

namespace Baikal
{
    std::unique_ptr<SceneIo> SceneIo::CreateSceneIoBinary()
    {
        return std::unique_ptr<SceneIo>(new SceneBinaryIo());
    }

    Scene1::Ptr SceneBinaryIo::LoadScene(std::string const& filename, std::string const& basepath) const
    {
        auto scene = Scene1::Create();

        auto image_io = ImageIo::CreateImageIo();

        std::string full_path = filename;

        std::ifstream in(full_path, std::ios::binary | std::ios::in);

        if (!in)
        {
            throw std::runtime_error("Cannot open file for reading");
        }

        std::unordered_map<std::string, Material::Ptr> mats;

        std::uint32_t num_meshes = 0;
        in.read((char*)&num_meshes, sizeof(std::uint32_t));

        LogInfo("Number of objects: ", num_meshes, "\n");

        for (auto i = 0U; i < num_meshes; ++i)
        {
            auto mesh = Mesh::Create();

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


            {
                std::uint32_t size = 0;
                in.read(reinterpret_cast<char*>(&size), sizeof(size));

                std::vector<char> buff(size);
                in.read(&buff[0], sizeof(char) * size);

                std::string name(buff.cbegin(), buff.cend());

                Material::Ptr material = nullptr;
                auto iter = mats.find(name);

                if (iter != mats.cend())
                {
                    material = iter->second;
                }
                else
                {
                    material = SingleBxdf::Create(SingleBxdf::BxdfType::kLambert);
                    material->SetName(name);
                    mats[name] = material;
                }

                mesh->SetMaterial(material);
            }

            scene->AttachShape(mesh);
        }

        auto  ibl_texture = image_io->LoadImage("../Resources/Textures/Canopus_Ground_4k.exr");

        auto ibl = ImageBasedLight::Create();
        ibl->SetTexture(ibl_texture);
        ibl->SetMultiplier(1.f);

        // TODO: temporary code to add directional light
        auto light = DirectionalLight::Create();
        light->SetDirection(RadeonRays::normalize(RadeonRays::float3(-1.1f, -0.6f, -0.4f)));
        light->SetEmittedRadiance(7.f * RadeonRays::float3(1.f, 0.95f, 0.92f));

        auto light1 = DirectionalLight::Create();
        light1->SetDirection(RadeonRays::float3(0.3f, -1.f, -0.5f));
        light1->SetEmittedRadiance(RadeonRays::float3(1.f, 0.8f, 0.65f));

        scene->AttachLight(light);
        //scene->AttachLight(light1);
        scene->AttachLight(ibl);

        return scene;
    }

    void SceneBinaryIo::SaveScene(Scene1 const& scene, std::string const& filename, std::string const& basepath) const
    {
        std::cout << "Saving scene...\n";
        std::string full_path = filename;

        std::ofstream out(full_path, std::ios::binary | std::ios::out);

        if (!out)
        {
            throw std::runtime_error("Cannot open file for writing");
        }

        auto default_material = SingleBxdf::Create(SingleBxdf::BxdfType::kLambert);
        default_material->SetName("default_material");

        auto num_shapes = (std::uint32_t)scene.GetNumShapes();
        out.write((char*)&num_shapes, sizeof(std::uint32_t));

        auto shape_iter = scene.CreateShapeIterator();

        for (; shape_iter->IsValid(); shape_iter->Next())
        {
            auto mesh = shape_iter->ItemAs<Mesh>();
            auto num_indices = (std::uint32_t)mesh->GetNumIndices();
            auto num_vertices = (std::uint32_t)mesh->GetNumVertices();
            auto num_normals = (std::uint32_t)mesh->GetNumNormals();
            auto num_uvs = (std::uint32_t)mesh->GetNumUVs();

            std::cout << "Saving mesh " << mesh->GetName() << " " << num_indices <<
                " " << num_vertices <<
                " " << num_normals <<
                " " << num_uvs << "\n";


            out.write((char*)&num_indices, sizeof(std::uint32_t));


            out.write((char*)&num_vertices, sizeof(std::uint32_t));


            out.write((char*)&num_normals, sizeof(std::uint32_t));


            out.write((char*)&num_uvs, sizeof(std::uint32_t));

            out.write((char const*)mesh->GetIndices(), mesh->GetNumIndices() * sizeof(std::uint32_t));
            out.write((char const*)mesh->GetVertices(), mesh->GetNumVertices() * sizeof(RadeonRays::float3));
            out.write((char const*)mesh->GetNormals(), mesh->GetNumNormals() * sizeof(RadeonRays::float3));
            out.write((char const*)mesh->GetUVs(), mesh->GetNumUVs() * sizeof(RadeonRays::float2));

            auto material = mesh->GetMaterial();

            if (!material)
            {
                material = default_material;
            }

            {
                auto material_name = material->GetName();

                if (material_name.empty())
                    material_name = "default_material";

                auto size = static_cast<std::uint32_t>(material_name.size());

                out.write(reinterpret_cast<char const*>(&size), sizeof(size));
                out.write(material_name.c_str(), sizeof(char) * size);
            }
        }

        std::cout << "Done...\n";
    }
}
