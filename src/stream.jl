function stream_create(config::StreamConfiguration; connection::NATS.Connection)
    validate(config)
    resp = NATS.request(JSON3.Object, "\$JS.API.STREAM.CREATE.$(config.name)", config; connection)
    throw_on_api_error(resp)
    resp.did_create
end

function stream_create(; connection::NATS.Connection, kwargs...)
    config = StreamConfiguration(; kwargs...)
    stream_create(config; connection)
end

function stream_update(config::StreamConfiguration; connection::NATS.Connection)
    validate(config)
    resp = NATS.request(JSON3.Object, "\$JS.API.STREAM.UPDATE.$(config.name)", config; connection)
    throw_on_api_error(resp)
    true
end

function stream_update(; connection::NATS.Connection, kwargs...)
    config = StreamConfiguration(; kwargs...)
    stream_update(config; connection)
end

function stream_create_or_update(config::StreamConfiguration; connection::NATS.Connection)
    try
        stream_update(config; connection)        
    catch err
        if err isa ApiError && err.code == 404
            stream_create(config; connection)
        else
            rethrow()
        end
    end
end

function stream_create_or_update(; connection::NATS.Connection, kwargs...)
    config = StreamConfiguration(; kwargs...)
    stream_create_or_update(config; connection)
end

function stream_delete(; connection::NATS.Connection, name::String)
    validate_name(name)
    resp = NATS.request(JSON3.Object, "\$JS.API.STREAM.DELETE.$(name)"; connection)
    throw_on_api_error(resp)
    resp.success
end

function stream_list(; connection::NATS.Connection)
    resp = NATS.request(JSON3.Object, "\$JS.API.STREAM.LIST"; connection)
    throw_on_api_error(resp)
    resp.streams
    # map(resp.streams) do s
    #     JSON3.read(JSON3.write(s), StreamInfo)
    # end 
end

function stream_names(; subject = nothing, connection::NATS.Connection, timer = Timer(5))
    req = isnothing(subject) ? nothing : "{\"subject\": \"$subject\"}"
    resp = NATS.request(JSON3.Object, "\$JS.API.STREAM.NAMES", req; connection, timer)
    throw_on_api_error(resp)
    # total, offset, limit = resp.total, resp.offset, resp.limit
    #TODO: pagination
    @something resp.streams String[]
end
