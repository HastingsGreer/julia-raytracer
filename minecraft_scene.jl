include("raytracer.jl")
using Random

using NRRD
using Images
v = load("../mc/r.0.0.nrrd")
v = feature_transform(v .== 1)
const volume = Float32.(distance_transform(v))

volume[volume .== 0] .= 0
function render_scene(x, y, alpha, beta)
   dirHorizonAngle = x

   dirVertAngle = y

   cameraPosition = Vec3(200, 200, 73)

   camDirMat = twistmat(dirHorizonAngle) * vertmat(dirVertAngle)
   u = camDirMat * Vec3(1, 0, 0)
   v = camDirMat * Vec3(0, -1, 0)
   w = camDirMat * Vec3(0, 0, 1)

   horiz = 512
   vert = 512

   room = Room(
      [],

      WorldCamera(
         cameraPosition,
         u,
         v,
         w,
         0.1,
         0.1 * vert / horiz,
         0.1,
         horiz,
         vert,
      ),
      volume
   )


   push!(room.lights, Light(Vec3(100, 200, 200), 19000 .* white))
   push!(room.lights, Light(Vec3(300, 200, 200), 19000 .* white))

   canvas = Array{Vec3}(undef, room.camera.v, room.camera.h)
   render(room, canvas)
   return canvas
end

println("rendering")
arr = render_scene(.1, 3.9, 0, 0)
println("convertingtoimage")
using Colors
using Images

function toImage(arr)
   #arr = map(x -> log.(x .+ .001), arr)
   max_in_arr = maximum(map(maximum, arr))
   function to_color(px)
      return RGB(px ./ max_in_arr...)
   end
   return to_color.(arr)
end
println("done")
toImage(arr)
