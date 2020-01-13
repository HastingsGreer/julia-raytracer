using CUDAdrv, CUDAnative, CuArrays


struct squarer
    mine::Int32
end

struct ident
    mine::Int32
end

function doit(x::squarer)
    return x.mine^2
end

function doit(x::ident)
    return x.mine
end

#arr2 = Vector{Union{squarer, ident}}()
arr2 = Vector{squarer}()
println("ji")

function do_kernel(inp, out)
    i = threadIdx().x

    @inbounds out[i] = length(out)

    return nothing
end


out = Vector{Int32}(undef, 3)

push!(arr2, squarer(3))
push!(arr2, squarer(3))
push!(arr2, squarer(3))

cu_arr2 = CuArray(arr2)
cu_out = CuArray(out)

@device_code_warntype @cuda threads=3 do_kernel(cu_arr2, cu_out)

synchronize()
println(collect(cu_out))
