function b(::Val{i}) where {i}
    return fakeRecursive(Val(i))
end




function fakeRecursive(::Val{i}) where {i}
    if i == 0
        println("hi")
    else
        println(i)
        b(Val(i - 1))
    end
end

fakeRecursive(Val(12))
