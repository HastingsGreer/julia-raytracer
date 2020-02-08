using StaticArrays
using CUDAnative
using CuTextures
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
   return Mat3(1, 0, 0,
   0, cos(angle), -sin(angle),
   0, sin(angle), cos(angle))
end

function horizmat(angle)
   return Mat3(cos(angle), 0, -sin(angle),
   0, 1, 0,
   sin(angle), 0, cos(angle))
end

function twistmat(angle)
   return Mat3(cos(angle), -sin(angle), 0, sin(angle), cos(angle), 0, 0, 0, 1)
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

mutable struct Room
   lights::Vector{Light}
   camera::WorldCamera
   volume::Array{Float32, 3}
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
   volume,
   place::Vec3,
   lights,
   in::Ray,
   ::Val{recursions},
) where {recursions}
   prof = PhongProfile(black, (0.0f0, 1.0f0, 0.0f0), (1.0f0, 1.0f0, 1.0f0), 20.0f0, 0.5f0)


   c = prof.ambient
   norma = normal(volume, place)

   norm = c .* 0 .+ norma

   vec2camera = -1 .* in.dir
   for l in lights
      vec2Light = l.pos .- place
      dist2Light2 = dot(vec2Light, vec2Light)

      unit2Light = unit(vec2Light)
      res = intersectionV(volume, Ray(place .+ .1 .* unit2Light, unit2Light))

      if ((!res.didIntersect) || res.t * res.t > dist2Light2)
         diffuse_coeff = dot(unit2Light, norm)
         if diffuse_coeff > 0
            c = @. c + l.color * diffuse_coeff * prof.diffuse / dist2Light2
         end
         if !(prof.spectral == black)

            spectralMult = dot(norm, unit(unit2Light .+ unit(vec2camera)))
            if spectralMult > 0
               c = c .+
                   l.color .* (prof.spectral *
                    CUDAnative.pow_fast(spectralMult, prof.power) /
                    dist2Light2)
            end
         end
      end
   end
   #=if prof.reflectivity != 0 && recursions != 0
      c = c .* (1 - prof.reflectivity) .+
          prof.reflectivity .* trace(
         primitives,
         lights,
         Ray(place, norm .* (2 * dot(norm, vec2camera)) .- vec2camera),
         Val{recursions - 1}(),
      )
   end =#
   return c
end

struct IntersectionResult
   t::Float32
   didIntersect::Bool
   nearest::Int64
end

function getVScaled(volume::CuDeviceTexture, curr_position::Vec3)
   return volume(
      curr_position[1] / 512.f0,
      curr_position[2] / 512.f0,
      curr_position[3] / 176.f0,
   )
end

function normal(volume::CuDeviceTexture, pos::Vec3)
   x = (
      getVScaled(volume, pos .+ (0.1f0, 0f0, 0f0)) -
      getVScaled(volume, pos .+ (-.1f0, 0f0, 0f0)),
      getVScaled(volume, pos .+ (0f0, 0.1f0, 0f0)) -
      getVScaled(volume, pos .+ (0f0, -.1f0, 0f0)),
      getVScaled(volume, pos .+ (0f0, 0f0, 0.1f0)) -
      getVScaled(volume, pos .+ (0f0, 0f0, -.1f0)) + .00001f0,
   )
   return x ./ magnitudel(x) #unit(x)
end
function intersectionV(volume, other::Ray)

   curr_position = other.tail;
   step::Float32 = 0;
   t::Float32 = 0
   for N in 1:120
      @inbounds step = 1.06 * getVScaled(volume, curr_position)

      if step < .05
         break
      end

      t += step

      curr_position = curr_position .+ other.dir .* step
   end

   if step > .1
      return IntersectionResult(-1, false, -1)
   end
   return IntersectionResult(t, true, 1)
end
using CUDAnative, CUDAdrv

using CuArrays


function render_kernel(volume, lights, camera, canvas)
   h = blockIdx().x
   v = threadIdx().x + 512 * (blockIdx().y - 1)
   @inbounds canvas[v, h] = trace(volume, lights, makeRay(camera, h, v), Val(1))
   return

end
using Base.Threads
function render(room::Room, canvas::Array{Vec3})
   if(true)


      cu_volume = CuTexture(CuTextureArray(room.volume))
      cu_lights = CuArray(room.lights)
      cu_canvas = CuArray(canvas)

      @cuda blocks=(room.camera.h, 1) threads=512 render_kernel(cu_volume, cu_lights, room.camera, cu_canvas)

      synchronize()

      canvas .= collect(cu_canvas)
   else
      Threads.@threads for h=1:room.camera.h
         for v=1:room.camera.v
            canvas[v, h] = sqrt.(trace(room.volume, room.lights, makeRay(room.camera, h, v), Val(4)))
         end
      end
   end

   return canvas
end
function trace(volume, lights, ray::Ray, ::Val{recursions}) where {recursions}
   res = intersectionV(volume, ray)
   if res.didIntersect
      #return white .* res.t
      ##=@inbounds elem = primitives[res.nearest]
      return shade(
         volume,
         ray.tail .+ ray.dir .* res.t,
         lights,
         ray,
         Val{recursions}()
      )
   else
      return blue
   end
end

const blue = Vec3(.1f0, .1f0, .4f0)
const white = Vec3(1, 1, 1)
const black = Vec3(0, 0, 0)
