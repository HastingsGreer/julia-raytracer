
using StaticArrays

Vec3 = SVector{3,Float32}

function dot(a::Vec3, b::Vec3)
   return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

function unit(v)
   return v ./ sqrt(sum(v .* v))
end

Mat3 = SMatrix{3,3,Float32}

function vertmat(angle)
   return Mat3(1, 0, 0, 0, cos(angle), -sin(angle), 0, sin(angle), cos(angle))
end

function horizmat(angle)
   return Mat3(cos(angle), 0, -sin(angle), 0, 1, 0, sin(angle), 0, cos(angle))
end

struct WorldCamera
   pos::Vec3
   vinc::Vec3
   hinc::Vec3
   topLeft::Vec3
   h::Int64
   v::Int64
end

struct Ray
   tail::Vec3
   dir::Vec3
end

struct Light
   pos::Vec3
   color::Vec3
end

abstract type Renderable end

mutable struct Room
   lights::Vector{Light}
   primitives::Vector{Renderable}
   camera::WorldCamera
end

struct PhongProfile
   ambient::Vec3
   diffuse::Vec3
   spectral::Vec3
   power::Float32
   reflectivity::Float32
end

function WorldCamera(
   pos,
   u,
   v,
   w,
   width,
   height,
   dist,
   hresolution,
   vresolution,
)
   u = unit(u)
   v = unit(v)
   w = unit(w)

   topLeft = @. u * width / -2 + v * height / -2 + w * dist
   hinc = @. u * width / hresolution
   vinc = @. v * height / vresolution

   return WorldCamera(pos, vinc, hinc, topLeft, hresolution, vresolution)
end

function makeRay(cam, h, v)
   dir = @. cam.topLeft + cam.hinc * h + cam.vinc * v
   return Ray(cam.pos, unit(dir))
end



function shade(r::Renderable, place::Vec3, room::Room, in::Ray, recursions::Int)
   c = r.prof.ambient
   norm = normal(r, place)
   vec2camera = -1 .* in.dir
   for l in room.lights
      vec2Light = l.pos .- place
      dist2Light2 = dot(vec2Light, vec2Light)
      unit2Light = unit(vec2Light)
      res = intersection(room, Ray(place, unit2Light))

      if ((!res.didIntersect) || res.t * res.t > dist2Light2)
         diffuse_coeff = dot(unit2Light, norm)
         if diffuse_coeff > 0
            c = @. c + l.color * r.prof.diffuse / dist2Light2
         end
         if !(r.prof.spectral == black)
            spectralMult = dot(norm, unit(unit2Light .+ unit(vec2camera)))
            if spectralMult > 0
               c = @. c +
                      l.color * r.prof.spectral * spectralMult^r.prof.power /
                      dist2Light2
            end
         end
      end
   end
   return c
end

struct IntersectionResult
   t::Float32
   didIntersect::Bool
   nearest::Union{Renderable,Nothing}
end

struct Plane <: Renderable
   point::Vec3
   norm::Vec3
   prof::PhongProfile
   Plane(point, norm, prof) = new(point, unit(norm), prof)
end

function intersection(p::Plane, other::Ray)
   distFromPlane = dot(p.norm, other.tail .- p.point)
   effectiveness = dot(p.norm, other.dir)
   t = -distFromPlane / effectiveness

   if (t > 0.001)
      return IntersectionResult(t, true, p)
   else
      return IntersectionResult(-1, false, nothing)
   end
end

function normal(p::Plane, place::Vec3)
   return p.norm
end

struct Sphere <: Renderable
   center::Vec3
   radius::Float32
   invradius::Float32
   prof::PhongProfile
   Sphere(center, radius, prof) = new(center, radius, 1 / radius, prof)
end

function intersection(sphere::Sphere, other::Ray)

   p = @. (other.tail - sphere.center) * sphere.invradius
   d = other.dir .* sphere.invradius
   dDotp = dot(d, p)
   discriminant = dDotp * dDotp - dot(d, d) * (dot(p, p) - 1)

   if discriminant < 0
      return IntersectionResult(-1, false, nothing)
   end
   if (-dDotp - sqrt(discriminant) > 0.001)

      return IntersectionResult(
         (-dDotp - sqrt(discriminant)) / dot(d, d),
         true,
         sphere,
      )
   end
   if (-dDotp + sqrt(discriminant) > 0.001)
      return IntersectionResult(
         (-dDotp + sqrt(discriminant)) / dot(d, d),
         true,
         sphere,
      )
   end

   return IntersectionResult(-1, false, nothing)
end

function normal(s::Sphere, place::Vec3)
   return unit(place .- s.center)
end





function render(r::Room)
   canvas = Array{Vec3}(undef, r.camera.h, r.camera.v)

   for h = 1:r.camera.h
      for v = 1:r.camera.v
         canvas[v, h] = trace(r, makeRay(room.camera, h, v))
      end
   end
   return canvas
end

function trace(r::Room, ray::Ray)
   res = intersection(r, ray)
   if res.didIntersect
      #return white
      return shade(res.nearest, ray.tail .+ ray.dir .* res.t, r, ray, 1)
   else
      return black
   end
end

function intersection(room::Room, ray::Ray)
   nearest = IntersectionResult(-1, false, nothing)
   for elem in room.primitives
      canidate = intersection(elem, ray)
      if canidate.t > 0.001
         if nearest.t > canidate.t || !nearest.didIntersect
            nearest = canidate
         end
      end
   end
   return nearest
end

#########################################################

const white = Vec3(1, 1, 1)
const black = Vec3(0, 0, 0)
dirHorizonAngle = 0

dirVertAngle = 0

cameraPosition = Vec3(0, 3, -10)

camDirMat = horizmat(dirHorizonAngle) * vertmat(dirVertAngle)
u = camDirMat * Vec3(1, 0, 0)
v = camDirMat * Vec3(0, -1, 0)
w = camDirMat * Vec3(0, 0, 1)

horiz = 512
vert = 512

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
   ),
)

push!(
   room.primitives,
   Sphere(Vec3(-4, 0, -7), 1, PhongProfile(black, white, black, 0, 0.5)),
)

push!(
   room.primitives,
   Sphere(Vec3(4, 0, -7), 1, PhongProfile(black, white, black, 0, 0.5)),
)

push!(
   room.primitives,
   Sphere(Vec3(-4, 0, 7), 2, PhongProfile(black, white, black, 0, 0.5)),
)

push!(
   room.primitives,
   Sphere(Vec3(4, 0, 7), 1, PhongProfile(black, 40 .*(.01, .01, .01), black, 0, 0.5)),
)
push!(room.lights, Light(Vec3(-4, 20, -3), 30 .* white))

push!(room.lights, Light(Vec3(-20, 0, 0), Vec3(1, 0, 0)))

arr = render(room)

println("done")



using Colors
using Images

function toImage(arr)
   max_in_arr = maximum(arr)
   function to_color(px)
      return RGB(10 .* px...)
   end
   return to_color.(arr)
end
toImage(arr)
