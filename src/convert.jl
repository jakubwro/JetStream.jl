import Base.convert

# function convert(::Type{ConsumerInfo}, msg::NATS.Msg)
#     response  = JSON3.read(NATS.payload(msg))
#     if haskey(response, :error)
#         throw(JSON3.read(JSON3.write(response.error), ApiError))
#     end
#     JSON3.read(NATS.payload(msg), ConsumerInfo)
# end

const api_type_map = Dict(
    "io.nats.jetstream.api.v1.consumer_create_response" => ConsumerInfo,
    "io.nats.jetstream.api.v1.stream_create_response" => StreamInfo,
    "io.nats.jetstream.api.v1.stream_delete_response" => ApiResult
)

function convert(::Type{T}, msg::NATS.Msg) where { T <: ApiResponse }
    # TODO: check headers
    response  = JSON3.read(@view msg.payload[(begin + msg.headers_length):end])
    if haskey(response, :error)
        err = StructTypes.constructfrom(ApiError, response.error)
        throw(err)
    end
    type = get(api_type_map, response.type, nothing)
    isnothing(type) && error("Conversion not defined for `$(response.error)`")
    type = api_type_map[response.type]
    StructTypes.constructfrom(type, response)
end

function convert(::Type{Union{T, ApiError}}, msg::NATS.Msg) where { T <: ApiResponse }
    # TODO: check headers
    pl = NATS.payload(msg)
    pl = replace(pl, "0001-01-01T00:00:00Z" => "0001-01-01T00:00:00.000Z")
    response  = JSON3.read(pl)

    if haskey(response, :error)
        StructTypes.constructfrom(ApiError, response.error)
    else
        type = get(api_type_map, response.type, nothing)
        isnothing(type) && error("Conversion not defined for `$(response.type)`")
        type = api_type_map[response.type]
        StructTypes.constructfrom(type, response)
    end

end
