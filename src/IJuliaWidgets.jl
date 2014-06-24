require("React")
require("Interact")

module IJuliaWidgets

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
using  IJulia.CommManager
import IJulia.CommManager: register_comm
import Base: writemime, mimewritable

export register_comm

const comms = Dict{Signal, Comm}()

function send_update(comm :: Comm, v)
    # do this better!!
    # Thoughts:
    #    Queue upto 3, buffer others
    #    Diff and send
    #    Is display_dict the right thing?
    send_comm(comm, ["value" => Main.IJulia.display_dict(v)])
end


Main.IJulia.display_dict(x :: Signal) =
    Main.IJulia.display_dict(x.value)

function IJulia.metadata(x :: Signal)
    if !haskey(comms, x)
        # One Comm channel per signal object
        comm = Comm(:Signal)

        comms[x] = comm   # Backend -> Comm
        # prevent resending the first time?
        lift(v -> send_update(comm, v), x)
    else
        comm = comms[x]
    end
    return ["reactive"=>true, "comm_id"=>comm_id(comm)]
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
    println(methods(CommManager.on_msg))
end


##################### IPython IPEP 23: Backbone.js Widgets #################
function create_widget(widget :: InputWidget)
    comm = Comm(:WidgetModel, true)
    # Send a full state update message.
    widget_name = string(typeof(widget))

    state = JSON.parse(JSON.json(widget)) # Is there a better way of doing this?
    state["msg_throttle"] = 3
    state["_view_name"] = "$(widget_name)Widget"

    
end

end
