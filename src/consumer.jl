
const DEFAULT_NEXT_TIMEOUT_SECONDS = 5


function create_or_update(connection::NATS.Connection, consumer_config::ConsumerConfiguration, stream::String)
    consumer_name = @something consumer_config.name consumer_config.durable_name randstring(20)
    subject = "\$JS.API.CONSUMER.CREATE.$stream.$consumer_name"
    req_data = Dict(:stream_name => stream, :config => consumer_config)
    # if !isnothing(action)
    #     req_data[:action] = action
    # end
    NATS.request(ConsumerInfo, connection, subject, JSON3.write(req_data))
end

function create_or_update(consumer::ConsumerConfiguration, stream::StreamInfo)
end

function create(connection::NATS.Connection, consumer::ConsumerConfiguration, stream::String)
    create_or_update(connection, consumer, stream)
end

function create(connection::NATS.Connection, consumer::ConsumerConfiguration, stream::StreamInfo)
    create_or_update(connection, consumer, stream.config.name)
end

function update(consumer::ConsumerConfiguration, stream::Union{StreamInfo, String})

end

function next(connection::NATS.Connection, stream::String, consumer::String; no_wait = false, timer = Timer(DEFAULT_NEXT_TIMEOUT_SECONDS))
    # if no_wait
        # NATS.request("\$JS.API.CONSUMER.MSG.NEXT.$stream.$consumer", "{\"no_wait\": true}"; connection)
    # else
        NATS.request(connection, "\$JS.API.CONSUMER.MSG.NEXT.$stream.$consumer"; timer)
    # end 
end

function next(connection::NATS.Connection, consumer::ConsumerInfo; no_wait = false, timer = Timer(DEFAULT_NEXT_TIMEOUT_SECONDS))
    req = "{\"no_wait\": $no_wait}"
    msgs = NATS.request(connection, 1, "\$JS.API.CONSUMER.MSG.NEXT.$(consumer.stream_name).$(consumer.name)", req; timer)
    if isempty(msgs)
        error("No replies.")
    end
    msg = only(msgs)
    msg
end

# function next(
#     connection::NATS.Connection,
#     consumer::ConsumerInfo;
#     no_wait::Bool = false;
#     timer = Timer(DEFAULT_NEXT_TIMEOUT_SECONDS))

#     next(connection, consumer.stream_name, consumer.name; no_wait, timer)
# end

function consumer_create_or_update(stream_name::String, config::ConsumerConfiguration; connection::NATS.Connection, action = nothing)
    consumer_name = @something config.name config.durable_name randstring(20)
    subject = "\$JS.API.CONSUMER.CREATE.$stream_name.$consumer_name"
    req_data = Dict(:stream_name => stream_name, :config => config)
    if !isnothing(action)
        req_data[:action] = action
    end
    resp = NATS.request(ConsumerInfo, connection, subject, JSON3.write(req_data))
    # throw_on_api_error(resp)
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

function delete(connection::NATS.Connection, consumer::ConsumerInfo)
    @warn "not implemented"
end

function next(stream::String, consumer::String; no_wait = false, timer = Timer(DEFAULT_NEXT_TIMEOUT_SECONDS), connection::NATS.Connection)
    # if no_wait
        # NATS.request("\$JS.API.CONSUMER.MSG.NEXT.$stream.$consumer", "{\"no_wait\": true}"; connection)
    # else
        NATS.request(connection, "\$JS.API.CONSUMER.MSG.NEXT.$stream.$consumer"; timer)
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
function ack(msg::NATS.Msg; connection::NATS.Connection)
    isnothing(msg.reply_to) && error("No reply subject for msg $msg.")
    !startswith(msg.reply_to, "\$JS.ACK") && @warn "`ack` sent for message that don't need acknowledgement." 
    NATS.publish(connection, msg.reply_to)
end

"""
Mark message as undelivered, what avoid waiting for timeout before redelivery.
"""
function nak(msg::NATS.Msg; connection::NATS.Connection)
    isnothing(msg.reply_to) && error("No reply subject for msg $msg.")
    !startswith(msg.reply_to, "\$JS.ACK") && @warn "`nak` sent for message that don't need acknowledgement." 
    NATS.publish(connection, msg.reply_to, "-NAK")
end
