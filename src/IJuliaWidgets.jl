require("React")
require("Interact")

module IJuliaWidgets

using JSON
using React
using Interact

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

export register_comm, metadata, display_dict

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
    return ["reactive"=>true, "comm_id"=>string(comm_id(comm))]
end

# Render the value of a signal.
mimewritable(io :: IO, m :: MIME, s :: Signal) =
    mimewritable(m, s.value)


writemime(io:: IO, m :: MIME, s :: Signal) =
    writemime(io :: IO, m, s.value)

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
view_name(w::InputWidget) = string(typeof(w), "View")

## ✓CheckboxWidget
## ✓ToggleButtonWidget
## ✓ButtonWidget
## ? ContainerWidget
## ? PopupWidget
## ✓FloatSliderWidget
## T BoundedFloatTextWidget
## T FloatProgressWidget
## T FloatTextWidget
## ? ImageWidget
## ✓IntSliderWidget
## ? BoundedIntTextWidget
## T IntProgressWidget
## T IntTextWidget
## ? AccordionWidget
## ? TabWidget
## ? ToggleButtonsWidget
## T RadioButtonsWidget
## T DropdownWidget
## T SelectWidget
## ? HTMLWidget
## ? LatexWidget
## ✓TextareaWidget
## ✓TextWidget

view_name{T<:Integer}(::Slider{T}) = "IntSliderView"
view_name{T<:FloatingPoint}(::Slider{T}) = "FloatSliderView"

# Add state data to the message
function add_state!(statemsg, w::InputWidget)
    attrs = names(w)
    for n in attrs
        if n == :input continue end
        statemsg[n] = getfield(w, n)
    end
end

function update_widget(comm :: Comm, w :: InputWidget)
    msg = Dict()
    msg["method"] = "update"
    state = Dict()
    state["msg_throttle"] = 3
    state["_view_name"] = view_name(w)
    state["description"] = w.label
    state["visible"] = true
    state["disabled"] = false
    add_state!(state, w)
    msg["state"] = state
    send_comm(comm, msg)
end

function create_widget(w :: InputWidget)
    comm = Comm(:WidgetModel)

    # Send a full state update message.
    update_widget(comm, w)
    send_comm(comm, ["method"=>"display"])

    # comm on_msg event handler: send value to the signal graph
    function CommManager.on_msg(::Comm{:WidgetModel, comm_id(comm)}, msg)
        if msg.content["data"]["method"] == "backbone"
            Interact.recv(w, msg.content["data"]["sync_data"]["value"])
        end
    end
end

end
