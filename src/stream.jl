

abstract type JetStreamPayload end

@enum SteramRetentionPolicy limits interest workqueue
@enum StreamStorage file memory
@enum StreamCompression none s2

@kwdef struct SubjectTransform
    "The subject transform source"
    src::String
    "The subject transform destination"
    dest::String
end
@kwdef struct Placement
    "The desired cluster name to place the stream"
    cluster::String
    "Tags required on servers hosting this stream"
    tags::Union{Vector{String}, Nothing} = nothing
end

@kwdef struct ExternalStreamSource
    "The subject prefix that imports the other account/domain $JS.API.CONSUMER.> subjects"
    api::String
    "The delivery subject to use for the push consumer"
    deliver::Union{String, Nothing} = nothing
end

@kwdef struct StreamSource
    "Stream name"
    name::Union{String, Nothing}
    "Sequence to start replicating from"
    opt_start_seq::Union{UInt64, Nothing} = nothing
    "Time stamp to start replicating from"
    opt_start_time::Union{DateTime, Nothing} = nothing
    "Replicate only a subset of messages based on filter"
    filter_subject::Union{String, Nothing} = nothing
    "The subject filtering sources and associated destination transforms"
    subject_transforms::Union{Vector{SubjectTransform}, Nothing} = nothing
    external::Union{ExternalStreamSource, Nothing} = nothing
end

@kwdef struct Republish
    "The source subject to republish"
    src::String
    "The destination to publish to"
    dest::String
    "Only send message headers, no bodies"
    headers_only::Union{Bool, Nothing} = nothing
end

@kwdef struct StreamConsumerLimit
    "Maximum value for inactive_threshold for consumers of this stream. Acts as a default when consumers do not set this value."
    inactive_threshold::Union{Int64, Nothing} = nothing
    "Maximum value for max_ack_pending for consumers of this stream. Acts as a default when consumers do not set this value."
    max_ack_pending::Union{Int64, Nothing} = nothing
end

@kwdef struct StreamConfiguration <: JetStreamPayload
    "A unique name for the Stream."
    name::String
    "A short description of the purpose of this stream"
    description::Union{String, Nothing} = nothing
    "A list of subjects to consume, supports wildcards. Must be empty when a mirror is configured. May be empty when sources are configured."
    subjects::Union{Vector{String}, Nothing} = nothing
    "Subject transform to apply to matching messages"
    subject_transform::Union{SubjectTransform, Nothing} = nothing
    "How messages are retained in the Stream, once this is exceeded old messages are removed."
    retention::SteramRetentionPolicy = limits
    "How many Consumers can be defined for a given Stream. -1 for unlimited."
    max_consumers::Int64 = -1
    "How many messages may be in a Stream, oldest messages will be removed if the Stream exceeds this size. -1 for unlimited."
    max_msgs::Int64 = -1
    "For wildcard streams ensure that for every unique subject this many messages are kept - a per subject retention limit"
    max_msgs_per_subject::Union{Int64, Nothing} = nothing
    "How big the Stream may be, when the combined stream size exceeds this old messages are removed. -1 for unlimited."
    max_bytes::Int64 = -1
    "Maximum age of any message in the stream, expressed in nanoseconds. 0 for unlimited."
    max_age::Int64 = 0
    "The largest message that will be accepted by the Stream. -1 for unlimited."
    max_msg_size::Union{Int32, Nothing} = nothing
    "The storage backend to use for the Stream."
    storage::StreamStorage = file
    "Optional compression algorithm used for the Stream."
    compression::Union{StreamCompression, Nothing} = nothing
    "A custom sequence to use for the first message in the stream"
    first_seq::Union{UInt64, Nothing} = nothing
    "How many replicas to keep for each message."
    num_replicas::Int64 = 1
    "Disables acknowledging messages that are received by the Stream."
    no_ack::Union{Bool, Nothing} = nothing
    "When a Stream reach it's limits either old messages are deleted or new ones are denied"
    discard::Union{String, Nothing} = nothing
    "The time window to track duplicate messages for, expressed in nanoseconds. 0 for default"
    duplicate_window::Union{Int64, Nothing} = nothing
    "Placement directives to consider when placing replicas of this stream, random placement when unset"
    placement::Union{Placement, Nothing} = nothing
    "Maintains a 1:1 mirror of another stream with name matching this property.  When a mirror is configured subjects and sources must be empty."
    mirror::Union{StreamSource, Nothing} = nothing
    "List of Stream names to replicate into this Stream"
    sources::Union{Vector{StreamSource}, Nothing} = nothing
    "Sealed streams do not allow messages to be deleted via limits or API, sealed streams can not be unsealed via configuration update. Can only be set on already created streams via the Update API"
    sealed::Union{Bool, Nothing} = nothing
    "Restricts the ability to delete messages from a stream via the API. Cannot be changed once set to true"
    deny_delete::Union{Bool, Nothing} = nothing
    "Restricts the ability to purge messages from a stream via the API. Cannot be change once set to true"
    deny_purge::Union{Bool, Nothing} = nothing
    "Allows the use of the Nats-Rollup header to replace all contents of a stream, or subject in a stream, with a single new message"
    allow_rollup_hdrs::Union{Bool, Nothing} = nothing
    "Allow higher performance, direct access to get individual messages"
    allow_direct::Union{Bool, Nothing} = nothing
    "Allow higher performance, direct access for mirrors as well"
    mirror_direct::Union{Bool, Nothing} = nothing
    republish::Union{Republish, Nothing} = nothing
    "When discard policy is new and the stream is one with max messages per subject set, this will apply the new behavior to every subject. Essentially turning discard new from maximum number of subjects into maximum number of messages in a subject."
    discard_new_per_subject::Union{Bool, Nothing} = nothing
    # "Additional metadata for the Stream"
    # metadata::Union{Dict{String, String}, Nothing} = nothing # TODO: what is this for?
    "Limits of certain values that consumers can set, defaults for those who don't set these settings"
    consumer_limits::Union{StreamConsumerLimit, Nothing} = nothing
end

function validate(stream_configuration::StreamConfiguration)
    validate_name(stream_configuration.name)
    true
end

StructTypes.omitempties(::Type{StreamConfiguration}) = true

function throw_on_api_error(response::JSON3.Object, message::String)
    if haskey(response, :error)
        error("$message: $(response.error.description).")
    end
end

function stream_create(config::StreamConfiguration; connection::NATS.Connection)
    validate(config)
    resp = NATS.request(JSON3.Object, "\$JS.API.STREAM.CREATE.$(config.name)", config; connection)
    throw_on_api_error(resp, "Failed to create stream \"$(config.name)\"")
    resp.did_create
end

function stream_create(; connection::NATS.Connection, kwargs...)
    config = StreamConfiguration(; kwargs...)
    stream_create(config; connection)
end

# function stream_update(; connection::NATS.Connection, kwargs...)
#     config = NATS.from_kwargs(StreamConfiguration, DEFAULT_STREAM_CONFIGURATION, kwargs)
#     validate_name(config.name)
#     resp = NATS.request(JSON3.Object, "\$JS.API.STREAM.UPDATE.$(config.name)", config; connection)
#     haskey(resp, :error) && error("Failed to update stream \"$(config.name)\": $(resp.error.description).")
#     true
# end

function stream_delete(; connection::NATS.Connection, name::String)
    validate_name(name)
    resp = NATS.request(JSON3.Object, "\$JS.API.STREAM.DELETE.$(name)"; connection)
    throw_on_api_error(resp, "Failed to delete stream \"$(name)\"")
    resp.success
end

# function stream_list(; connection::NATS.Connection)
#     resp = NATS.request(JSON3.Object, "\$JS.API.STREAM.LIST"; connection)
#     haskey(resp, :error) && error("Failed to get stream list: $(resp.error.description).")
#     #TODO: pagination
#     resp.streams
# end

function stream_names(; subject = nothing, connection::NATS.Connection, timer = Timer(5))
    req = isnothing(subject) ? nothing : "{\"subject\": \"$subject\"}"
    resp = NATS.request(JSON3.Object, "\$JS.API.STREAM.NAMES", req; connection, timer)
    throw_on_api_error(resp, "Failed to get stream names$(isnothing(subject) ? "" : " for subject \"$subject\"")")
    # total, offset, limit = resp.total, resp.offset, resp.limit
    #TODO: pagination
    @something resp.streams String[]
end
