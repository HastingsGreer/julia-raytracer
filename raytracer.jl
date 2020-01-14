using StaticArrays
using CUDAnative
Vec3 = SVector{3,Float32}

function dot(a::Vec3, b::Vec3)
   return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

function unit(v::Vec3)

   return v ./ magnitudel(v)
end

function random_hemisphere(v)
   x = unit(Vec3(Random.rand() * 2 - 1, Random.rand() * 2 - 1, Random.rand() * 2 - 1))
   eff = dot(x, v)
   if(eff) < 0
      x = x .+ 2*evv.*v
   end
   return x
end

function cross(v1, v2)
   return Vec3(
      v1[2] * v2[3] - v1[3] * v2[2],
      v1[3] * v2[1] - v1[1] * v2[3],
      v1[1] * v2[2] - v1[2] * v2[1],
   )
end

function magnitudel(v)
   return sqrt(sum(v .* v))
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

struct PhongProfile
   ambient::Vec3
   diffuse::Vec3
   spectral::Vec3
   power::Float32
   reflectivity::Float32
end

abstract type Renderable end

struct Plane <: Renderable
   point::Vec3
   norm::Vec3
   prof::PhongProfile
   idx::Int64
   Plane(point, norm, prof, idx) = new(point, unit(norm), prof, idx)
end

struct Sphere <: Renderable
   center::Vec3
   radius::Float32
   invradius::Float32
   prof::PhongProfile
   idx::Int64
   Sphere(center, radius, prof, idx) =
      new(center, radius, 1 / radius, prof, idx)
end

struct Triangle <: Renderable
   v1::Vec3
   v2::Vec3
   v3::Vec3
   e1::Vec3
   e2::Vec3
   norm::Vec3
   prof::PhongProfile
   idx::Int64
   Triangle(v1, v2, v3, prof, idx) =
      new(v1, v2, v3, v2 .- v1, v3 .- v1, unit(cross(v2 .- v1, v3 .- v1)))
end

mutable struct Room
   lights::Vector{Light}
   primitives::Vector{Sphere}
   camera::WorldCamera
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

function shade(
   r::Sphere,
   place::Vec3,
   lights,
   primitives,
   in::Ray,
   ::Val{recursions},
) where {recursions}
   c = r.prof.ambient
   norm = normal(r, place)
   vec2camera = -1 .* in.dir
   for l in lights
      vec2Light = l.pos .- place
      dist2Light2 = dot(vec2Light, vec2Light)

      unit2Light = unit(vec2Light)
      res = intersection_list(primitives, Ray(place, unit2Light))

      if ((!res.didIntersect) || res.t * res.t > dist2Light2)
         diffuse_coeff = dot(unit2Light, norm)
         if diffuse_coeff > 0
            c = @. c + l.color * diffuse_coeff * r.prof.diffuse / dist2Light2
         end
         if !(r.prof.spectral == black)

            spectralMult = dot(norm, unit(unit2Light .+ unit(vec2camera)))
            if spectralMult > 0
               c = c .+
                   l.color .* (r.prof.spectral *
                    CUDAnative.pow_fast(spectralMult, r.prof.power) /
                    dist2Light2)
            end
         end
      end
   end
   if r.prof.reflectivity != 0 && recursions != 0
      c = c .* (1 - r.prof.reflectivity) .+
          r.prof.reflectivity .* trace(
         primitives,
         lights,
         Ray(place, norm .* (2 * dot(norm, vec2camera)) .- vec2camera),
         Val{recursions - 1}(),
      )
   end
   return c
end

struct IntersectionResult
   t::Float32
   didIntersect::Bool
   nearest::Int64
end

function intersection(p::Plane, other::Ray)
   distFromPlane = dot(p.norm, other.tail .- p.point)
   effectiveness = dot(p.norm, other.dir)
   t = -distFromPlane / effectiveness

   if (t > 0.001)
      return IntersectionResult(t, true, p.idx)
   else
      return IntersectionResult(-1, false, -1)
   end
end

function normal(p::Plane, place::Vec3)
   return p.norm
end

function intersection(sphere::Sphere, other::Ray)
   p = @. (other.tail - sphere.center) * sphere.invradius
   d = other.dir .* sphere.invradius
   dDotp = dot(d, p)
   discriminant = dDotp * dDotp - dot(d, d) * (dot(p, p) - 1)

   if discriminant < 0
      return IntersectionResult(-1, false, -1)
   end
   if (-dDotp - sqrt(discriminant) > 0.0000001)

      return IntersectionResult(
         (-dDotp - sqrt(discriminant)) / dot(d, d),
         true,
         sphere.idx,
      )
   end
   if (-dDotp + sqrt(discriminant) > 0.0000001)
      return IntersectionResult(
         (-dDotp + sqrt(discriminant)) / dot(d, d),
         true,
         sphere.idx,
      )
   end
   return IntersectionResult(-1, false, -1)
end

function normal(s::Sphere, place::Vec3)
   return unit(place .- s.center)
end

using CUDAnative, CUDAdrv

using CuArrays
function render_kernel(primitives, lights, camera, canvas)
   h = blockIdx().x
   v = threadIdx().x + 512 * (blockIdx().y - 1)
   @inbounds canvas[v, h] = trace(primitives, lights, makeRay(camera, h, v), Val(1))
   return

end
using Base.Threads
function render(room::Room, canvas::Array{Vec3})
   if(true)


      cu_primitives = CuArray(room.primitives)
      cu_lights = CuArray(room.lights)
      cu_canvas = CuArray(canvas)

      @cuda blocks=(room.camera.h, 2) threads=512 render_kernel(cu_primitives, cu_lights, room.camera, cu_canvas)

      synchronize()

      canvas .= collect(cu_canvas)
   else
      Threads.@threads for h=1:room.camera.h
         for v=1:room.camera.v
            canvas[v, h] = sqrt.(trace(room.primitives, room.lights, makeRay(room.camera, h, v), Val(4)))
         end
      end
   end

   return canvas
end
const blue = Vec3(.1f0, .1f0, .4f0)
function trace(primitives, lights, ray::Ray, ::Val{recursions}) where {recursions}
   res = intersection_list(primitives, ray)
   if res.didIntersect
      #return white
      @inbounds elem = primitives[res.nearest]
      return shade(
         elem,
         ray.tail .+ ray.dir .* res.t,
         lights,
         primitives,
         ray,
         Val{recursions}()
      )
   else
      return blue
   end
end

function intersection_list(primitives, ray::Ray)
   nearest = IntersectionResult(-1, false, -1)
   for elem in primitives
      canidate = intersection(elem, ray)
      if canidate.t > 0.001
         if nearest.t > canidate.t || !nearest.didIntersect
            nearest = canidate
         end
      end
   end
   return nearest
end

const white = Vec3(1, 1, 1)
const black = Vec3(0, 0, 0)
