include("raytracer.jl")

dirHorizonAngle = 0

dirVertAngle = -.2

cameraPosition = Vec3(0, 3, -10)

camDirMat = horizmat(dirHorizonAngle) * vertmat(dirVertAngle)
u = camDirMat * Vec3(1, 0, 0)
v = camDirMat * Vec3(0, -1, 0)
w = camDirMat * Vec3(0, 0, 1)

horiz = 1024
vert = 1024

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
   Plane(
      Vec3(0, -2, -0),
      (0, 1, 0),
      PhongProfile(black, Vec3(0.5, 0.5, 0.5), black, 0, 0.5),
      1,
   ),
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
push!(room.lights, Light(Vec3(-4, 200, -3), 50000 .* white))

push!(room.lights, Light(Vec3(-20, 0, 0), 200 .* Vec3(1, 0, 1)))

push!(room.lights, Light(Vec3(0, 0, 50), 20 .* Vec3(0, 1, 1)))
canvas = Array{Vec3}(undef, room.camera.h, room.camera.v)
@time arr = render(room, canvas)

println("done")



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
toImage(arr)
