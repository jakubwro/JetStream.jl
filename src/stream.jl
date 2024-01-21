function trycreate(connection::NATS.Connection, config::StreamConfiguration)::Union{StreamInfo, ApiError}
    validate(config)
    NATS.request(Union{StreamInfo, ApiError}, connection, "\$JS.API.STREAM.CREATE.$(config.name)", config)
end

function create(connection::NATS.Connection, config::StreamConfiguration)::Union{StreamInfo, ApiError}
    response = trycreate(connection, config::StreamConfiguration)
    if response isa ApiError
        throw(response)
    end
    response
end

function tryupdate(connection::NATS.Connection, config::StreamConfiguration)
    validate(config)
    NATS.request(Union{ApiError, StreamInfo}, connection, "\$JS.API.STREAM.UPDATE.$(config.name)", config)
end

function update(connection::NATS.Connection, config::StreamConfiguration)
    validate(config)
    response = NATS.request(StreamInfo, connection, "\$JS.API.STREAM.UPDATE.$(config.name)", config)
    if response isa ApiError
        throw(response)
    end
    response
end

function create_or_update(connection::NATS.Connection, stream::StreamConfiguration)
    res = tryupdate(connection, config)
    if res isa StreamInfo
        res
    elseif res isa ApiError
        err.code != 404 && throw(res)
        create(connection, stream)
    end
end

function trydelete(connection::NATS.Connection, stream::String)
    NATS.request(Union{ApiResult, ApiError}, connection, "\$JS.API.STREAM.DELETE.$(stream)")
end

function trydelete(connection::NATS.Connection, stream::StreamInfo)
    trydelete(connection, stream.config.name)
end

function delete(connection::NATS.Connection, stream::String)
    res = trydelete(connection, stream)
    if res isa ApiError
        throw(res)
    end
    res
end

function delete(connection::NATS.Connection, stream::StreamInfo)
    delete(connection, stream.config.name)
end

function info(connection::NATS.Connection,
              stream_name::String;
              deleted_details = false,
              subjects_filter::Union{String, Nothing} = nothing)
    validate_name(stream_name)
    msg = NATS.request(connection, "\$JS.API.STREAM.INFO.$(stream_name)")
    resp = NATS.payload(msg)
    # resp = replace(resp, "0001-01-01T00:00:00Z" => "0001-01-01T00:00:00.000Z") # Workaround for timestamp parsing.
    json = JSON3.read(resp)
    throw_on_api_error(json)
    JSON3.read(JSON3.write(json), StreamInfo)
end

function streams(::Type{StreamInfo}, connection::NATS.Connection, subject = nothing)
    result = StreamInfo[]
    offset = 0
    req = Dict()
    isnothing(subject) || (req[:subject] = subject)
    while true
        req[:offset] = offset
        msg = NATS.request(connection, "\$JS.API.STREAM.LIST", JSON3.write(req))
        resp = NATS.payload(msg)
        json = JSON3.read(resp)
        throw_on_api_error(json)
        for s in json.streams
            item = StructTypes.constructfrom(StreamInfo, s)
            push!(result, item)
        end
        offset = offset + json[:limit]
        if json[:total] <= offset
            break
        end
    end
    result
end

function streams(::Type{String}, connection::NATS.Connection, subject = nothing; timer = Timer(5))
    result = String[]
    offset = 0
    req = Dict()
    isnothing(subject) || (req[:subject] = subject)
    while true
        req[:offset] = offset
        json = NATS.request(JSON3.Object, connection, "\$JS.API.STREAM.NAMES", JSON3.write(req); timer)
        throw_on_api_error(json)
        isnothing(json.streams) && break
        for s in json.streams
            push!(result, s)
        end
        offset = offset + json[:limit]
        if json[:total] <= offset
            break
        end
    end
    result
end

function streams(connection::NATS.Connection, subject = nothing)
    streams(StreamInfo, connection, subject)
end

function msg_get(connection::NATS.Connection, stream::StreamInfo, subject)
    if stream.config.allow_direct
        replies = NATS.request(connection, 1, "\$JS.API.DIRECT.GET.$(stream.config.name)", "{\"last_by_subj\": \"$subject\"}")
        isempty(replies) && error("No replies.")
        m = first(replies)
        @show NATS.headers(m) m.subject m.reply_to
        m
    else
        replies = NATS.request(connection, "\$JS.API.STREAM.MSG.GET.$stream_name", "{\"last_by_subj\": \"\$KV.asdf.$subject\"}", 1)
        isempty(replies) && error("No replies.")
        first(replies)
    end
end

function msg_get(connection::NATS.Connection, stream::String, subject)
    replies = NATS.request(connection, 1, "\$JS.API.DIRECT.GET.$stream.$subject", nothing)
    isempty(replies) && error("No replies.")
    first(replies)
end

function msg_delete(stream_name::String, seq::UInt64; connection = NATS.connection(:default))
    replies = NATS.request(connection, "\$JS.API.STREAM.MSG.DELETE.$stream_name", "{\"seq\": \"\$KV.asdf.$subject\"}", 1)
    isempty(replies) && error("No replies.")
    first(replies)
end

function purge(connection::NATS.Connection, stream::String)
    replies = NATS.request(connection, 1, "\$JS.API.STREAM.PURGE.$stream", nothing)
end

function purge(connection::NATS.Connection, stream::StreamInfo)
    purge(connection, stream.name)
end
