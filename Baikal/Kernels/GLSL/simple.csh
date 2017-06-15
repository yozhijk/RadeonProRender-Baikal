#version 430
layout(local_size_x = 8, local_size_y = 8) in;
layout(rgba16f, binding = 0) uniform image2D img_output;

void main()
{
    vec4 pixel = vec4(0.0, 1.0, 0.0, 1.0);
    ivec2 pixel_coords = ivec2(gl_GlobalInvocationID.xy);

    // output to a specific pixel in the image
    //if ((pixel_coords.x & 0x1) ^ (pixel_coords.y & 0x1))
    imageStore(img_output, pixel_coords, pixel);
}