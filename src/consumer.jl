
const DEFAULT_NEXT_TIMEOUT_SECONDS = 5

function consumer_create_or_update(stream_name::String, config::ConsumerConfiguration; connection::NATS.Connection, action = nothing)
    consumer_name = @something config.name config.durable_name randstring(20)
    subject = "\$JS.API.CONSUMER.CREATE.$stream_name.$consumer_name"
    req_data = Dict(:stream_name => stream_name, :config => config)
    if !isnothing(action)
        req_data[:action] = action
    end
    resp = NATS.request(JSON3.Object, subject, JSON3.write(req_data); connection)
    throw_on_api_error(resp)
    resp.name
end

function consumer_create_or_update(stream_name::String; connection::NATS.Connection, action = nothing, kwargs...)
    config = ConsumerConfiguration(; kwargs...)
    consumer_create_or_update(stream_name, config; connection, action)
end

function consumer_create(stream_name::String; connection::NATS.Connection, kwargs...)
    consumer_create_or_update(stream_name; action = :create, connection, kwargs...)
end

function consumer_update(stream_name::String; connection::NATS.Connection, kwargs...)
    consumer_create_or_update(stream_name; action = :update, connection, kwargs...)
end

# function consumer_ordered(stream::String, name::String)

# end

# function consumer_delete()

# end

function next(stream::String, consumer::String; no_wait = false, timer = Timer(DEFAULT_NEXT_TIMEOUT_SECONDS), connection::NATS.Connection)
    # if no_wait
        # NATS.request("\$JS.API.CONSUMER.MSG.NEXT.$stream.$consumer", "{\"no_wait\": true}"; connection)
    # else
        NATS.request("\$JS.API.CONSUMER.MSG.NEXT.$stream.$consumer"; connection, timer)
    # end 
end

# function next(n::Int64, stream::String, consumer::String; connection::NATS.Connection)
#     # TODO: n validation
#     msgs = NATS.request("\$JS.API.CONSUMER.MSG.NEXT.$stream.$consumer", "{ \"batch\": $n}", n; connection)
#     msgs
# end

"""
Confirms message delivery to server.
"""
function ack(msg::NATS.Message; connection::NATS.Connection)
    isnothing(msg.reply_to) && error("No reply subject for msg $msg.")
    !startswith(msg.reply_to, "\$JS.ACK") && @warn "`ack` sent for message that don't need acknowledgement." 
    NATS.publish(msg.reply_to; connection)
end

"""
Mark message as undelivered, what avoid waiting for timeout before redelivery.
"""
function nak(msg::NATS.Message; connection::NATS.Connection)
    isnothing(msg.reply_to) && error("No reply subject for msg $msg.")
    !startswith(msg.reply_to, "\$JS.ACK") && @warn "`nak` sent for message that don't need acknowledgement." 
    NATS.publish(msg.reply_to; connection, payload = "-NAK")
end
