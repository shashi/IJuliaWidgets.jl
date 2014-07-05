using Interact

function handle_msg(w::InputWidget, msg)
    if msg.content["data"]["method"] == "backbone"
        Interact.recv(w, msg.content["data"]["sync_data"]["value"])
    end
end

function handle_msg(w::Button, msg)
    try
        if msg.content["data"]["method"] == "custom" &&
            msg.content["data"]["content"]["event"] == "click"
            # click event occured
            push!(w.input, nothing)
        end
    catch e
        warn(string("Couldn't handle Button message ", e))
    end
end

function handle_msg(w::Dropdown, msg)
    try
        if msg.content["data"]["method"] == "backbone"
            key = msg.content["data"]["sync_data"]["value_name"]
            if haskey(w.options, key)
                Interact.recv(w, w.options[key])
            end
        end
    catch e
        warn(string("Couldn't handle Selection message ", e))
    end
end
