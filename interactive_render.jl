using GtkReactive, Gtk.ShortNames
include("minecraft_scene.jl")

win = Window("circle with radius")
vbox = Box(:v)

push!(win, vbox)

my_canvas = canvas(UserUnit, 1024, 1024)
push!(vbox, my_canvas)

up_slider = slider(-5:.01:5)
side_slider = slider(-5:.01:5)

push!(vbox, up_slider)
push!(vbox, side_slider)


const max_in_arr = 2 #maximum(map(maximum, arr))
function to_color(px)
    return RGB(
    min(px[1] / max_in_arr, 1),
    min(px[2] / max_in_arr, 1),
    min(px[3] / max_in_arr, 1)
    )
end

function makeCircle(mouse, up_slider, side_slider)

    arr = render_scene(up_slider, side_slider, (mouse.position.x - 400) / 30, -(mouse.position.y - 400) / 30)


    return map(to_color, arr)

end

imgsig = map(makeCircle, my_canvas.mouse.motion, up_slider, side_slider)

redraw = draw(my_canvas, imgsig) do cnvs, image
    copy!(cnvs, image)
end

Gtk.showall(win)
0
