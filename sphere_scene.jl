include("raytracer.jl")
function render_scene(alpha, beta, x, y)
   dirHorizonAngle = x

   dirVertAngle = y

   cameraPosition = Vec3(alpha, 3, -10 + beta)

   camDirMat = horizmat(dirHorizonAngle) * vertmat(dirVertAngle)
   u = camDirMat * Vec3(1, 0, 0)
   v = camDirMat * Vec3(0, -1, 0)
   w = camDirMat * Vec3(0, 0, 1)

   horiz =400
   vert = 400

   room = Room(
      [],
      [],
      WorldCamera(
         cameraPosition,
         u,
         v,
         w,
         0.2,
         0.2 * vert / horiz,
         0.1,
         horiz,
         vert,
      ),
   )

   push!(
      room.primitives,
      Sphere(Vec3(0, -100, 0), 100, PhongProfile(black, (.5, .5, .5), black, 0, 0.5), 2),
   )

   push!(
      room.primitives,
      Sphere(Vec3(-4, 0, -7), 1, PhongProfile(black, white, black, 0, 0.5), 2),
   )

   push!(
      room.primitives,
      Sphere(
         Vec3(4, 0, -7),
         1,
         PhongProfile(black, (0, 1, 0), (1, 1, 1), 20, 0.5),
         3,
      ),
   )

   push!(
      room.primitives,
      Sphere(Vec3(-4, 0, 7), 2, PhongProfile(black, white, black, 0, 0.5), 4),
   )

   push!(
      room.primitives,
      Sphere(
         Vec3(4, 0, 7),
         1,
         PhongProfile(black, (1, 0.2, 0), (1, 1, 1), 10, 0.5),
         5,
      ),
   )
   push!(room.lights, Light(Vec3(-4, 200, -300), 50000 .* white))

   push!(room.lights, Light(Vec3(-20, 0 , beta), 200 .* Vec3(1, 0, 1)))

   push!(room.lights, Light(Vec3(0, 0, 50), 20 .* Vec3(0, 1, 1)))
   canvas = Array{Vec3}(undef, room.camera.h, room.camera.v)
   render(room, canvas)
   return canvas
end

println("rendering")
arr = render_scene(0, 0, 0, 0)
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
