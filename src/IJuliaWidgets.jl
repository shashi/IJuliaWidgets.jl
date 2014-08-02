require("React")
require("Interact")

module IJuliaWidgets

using JSON
using React
using Interact

import Interact.update_view
export mimewritable, writemime

if !isdefined(Main, :IJulia)
    error("IJuliaWidgets must be imported from inside an IJulia notebook")
end
    
const ijulia_js  = readall(joinpath(dirname(Base.source_path()), "ijulia.js"))

try
    display("text/html", """<script charset="utf-8">$(ijulia_js)</script>""")
catch
end

import IJulia
import IJulia: metadata, display_dict
using  IJulia.CommManager
import IJulia.CommManager: register_comm, comm_id
import Base: writemime, mimewritable

const comms = Dict{Signal, Comm}()

function send_update(comm :: Comm, v)
    # do this better!!
    # Thoughts:
    #    Queue upto 3, buffer others
    #    Diff and send
    #    Is display_dict the right thing?
    msg = Main.IJulia.display_dict(v)
    send_comm(comm, ["value" => msg])
end

display_dict(x :: Signal) =
    display_dict(x.value)

function metadata(x :: Signal)
    if !haskey(comms, x)
        # One Comm channel per signal object
        comm = Comm(:Signal)

        comms[x] = comm   # Backend -> Comm
        # prevent resending the first time?
        lift(v -> send_update(comm, v), x)
    else
        comm = comms[x]
    end
    return ["reactive"=>true,
            "comm_id"=>string(comm_id(comm))]
end

# Render the value of a signal.
mimewritable(io :: IO, m :: MIME, s :: Signal) =
    mimewritable(m, s.value)

writemime(io:: IO, m :: MIME, s :: Signal) =
    writemime(io, m, s.value)

function writemime{T <: InputWidget}(io::IO,
                                ::MIME{symbol("text/html")},
                                s::Signal{T})
    create_widget_signal(s)
end

writemime(io::IO, ::MIME{symbol("text/html")},
          w::InputWidget) =
              create_view(w)

## This is for our own widgets.
function register_comm{comm_id}(comm :: Comm{:InputWidget, comm_id}, msg)
    w_id = msg.content["data"]["widget_id"]
    w = get_widget(w_id)

    function CommManager.on_msg(::Comm{:InputWidget, symbol(comm_id)}, msg)
        v =  msg.content["data"]["value"]
        recv(w, v)
    end
end

JSON.print(io::IO, s::Signal) = JSON.print(io, s.value)

##################### IPython IPEP 23: Backbone.js Widgets #################

## ButtonView ✓
## CheckboxView ✓
## DropdownView ✓
## FloatSliderView ✓
## FloatTextView ✓
## IntSliderView ✓
## IntTextView ✓
## ProgressView
## RadioButtonsView ✓
## SelectView ✓
## TextareaView ✓
## TextView ✓
## ToggleButtonsView ✓
## ToggleButtonView ✓
## AccordionView W
## ContainerView W
## HTMLView W
## ImageView W
## LatexView W
## PopupView W
## TabView W

# catchall view name for widgets
view_name(w::InputWidget) = string(typeof(w).name, "View")
view_name{T<:Integer}(::Slider{T}) = "IntSliderView"
view_name{T<:FloatingPoint}(::Slider{T}) = "FloatSliderView"
view_name{T<:Integer}(::Textbox{T}) = "IntTextView"
view_name{T<:FloatingPoint}(::Textbox{T}) = "FloatTextView"
view_name(::Textbox) = "TextView"
view_name{view}(::Options{view}) = string(view, "View")

function metadata{T <: Widget}(x :: Signal{T})
    Dict()
end

const widget_comms = Dict{Widget, Comm}()
function update_view(w::InputWidget; src::Widget=w)
    msg = Dict()
    msg["method"] = "update"
    state = Dict()
    state["msg_throttle"] = 3
    state["_view_name"] = view_name(src)
    state["description"] = w.label
    state["visible"] = true
    state["disabled"] = false
    msg["state"] = merge(state, statedict(src))
    send_comm(widget_comms[w], msg)
end

function create_view(w::InputWidget)
    if haskey(widget_comms, w)
        comm = widget_comms[w]
    else
        comm = Comm(:WidgetModel)
        widget_comms[w] = comm
        # Send a full state update message.
        update_view(w)

        # dispatch messages to widget's handler
        function CommManager.on_msg(::Comm{:WidgetModel, comm_id(comm)}, msg)
            handle_msg(w, msg)
        end
        nothing # display() nothing
    end

    send_comm(comm, ["method"=>"display"])
end

const widget_signals = Dict{Signal{Widget}, Widget}
function create_widget_signal(s)
    if haskey(widget_signals, s)
        update_view(widget_signals[s], src=s.value)
    else
        create_view(s.value)
        widget_signals[s] = s.value
    end
end

include("statedict.jl")
include("handle_msg.jl")

end
