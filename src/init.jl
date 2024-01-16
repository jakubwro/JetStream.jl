
function needs_ack(msg::NATS.Msg)
    !isnothing(msg.reply_to) && startswith(msg.reply_to, "\$JS.ACK")
end

function jetstream_fallback_handler(nc::NATS.Connection, msg::NATS.Msg)
    if needs_ack(msg)
        @warn "No handler for $msg, sending `-NAK`."
        nak(nc, msg)
    end
end

function __init__()
    NATS.install_fallback_handler(jetstream_fallback_handler)
end