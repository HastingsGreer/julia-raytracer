using Images, TestImages, ColorTypes, FixedPointNumbers
using StaticArrays
using CuArrays, CUDAnative
using CuTextures
using NRRD

# Get the input image. Use RGBA to have 4 channels since CUDA textures can have only 1, 2 or 4 channels.
img = load("../mc/r.0.0.nrrd")
img = feature_transform(img .== 1)
img = distance_transform(img)


Vec3 = SVector{3,Float32}


println("transformed")

img = Float32.(img)
#
#img = img[:, 40, :]

#
# Create a texture memory object (CUDA array) and initilaize it with the input image content (from host).
texturearray = CuTextureArray(img)

# Create a texture object and bind it to the texture memory created above
texture = CuTexture(texturearray)

# Define an image warping kernel
function warp(dst, texture)

    i = (blockIdx().x - 1) * blockDim().x + threadIdx().x
    j = (blockIdx().y - 1) * blockDim().y + threadIdx().y
    u = (Float32(i) - 1f0) / (Float32(size(dst, 1)) - 1f0)
    v = (Float32(j) - 1f0) / (Float32(size(dst, 2)) - 1f0)

    #zzz = Vec3(9, 9, 9)

    x = u  #+ 0.02f0 * CUDAnative.sin(30v)
    y = v #+ 0.03f0 * CUDAnative.sin(20u)
    z = Float32(000)
    @inbounds dst[i,j] = texture(x,z,y)
    return nothing
end

# Create a 500x1000 CuArray for the output (warped) image
outimg_d = CuArray{eltype(img)}(undef, 500, 500)

# Execute the kernel
@device_code_warntype @cuda threads = (size(outimg_d, 1), 1) blocks = (1, size(outimg_d, 2)) warp(outimg_d, texture)

# Get the output image into host memory and save it to a file
outimg = Array(outimg_d)

using PyPlot
imshow(outimg)
colorbar()
savefig("out.png")
PyPlot.close_figs()
