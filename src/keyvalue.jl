
const KEY_VALUE_OPERATIONS = [:none, :put, :delete, :purge]

const MAX_HISTORY    = 64
const ALL_KEYS       = ">"
const LATEST_REVISION = UInt(0)

struct KeyValueEntry
    # Bucket is the bucket the data was loaded from.
    bucket::String
    # Key is the key that was retrieved.
    key::String
    # Value is the retrieved value.
    value::String
    # Revision is a unique sequence for this value.
    revision::UInt64
    # Created is the time the data was put in the bucket.
    created::NanoDate
    # Delta is distance from the latest value.
    delta::UInt64
    # Operation returns Put or Delete or Purge.
    operation::Symbol
end

struct KeyValue{TValue} <: AbstractDict{String, TValue}
    connection::NATS.Connection
    bucket::String
    stream_name::String
    value_type::DataType
end

connection(kv::KeyValue) = kv.connection
    
function KeyValue{T}(bucket::String; connection::NATS.Connection = NATS.connection(:default)) where T
    NATS.find_msg_conversion_or_throw(T)
    NATS.find_data_conversion_or_throw(T)
    try
        JetStream.info(connection, "KV_$bucket")
        KeyValue{T}(connection, bucket, "KV_$bucket", T)
    catch err
        (err isa ApiError && err.code == 404) || rethrow()
        @info "KV $bucket does not exists, creating now."
        keyvalue_create(bucket; connection)
        KeyValue{T}(connection, bucket, "KV_$bucket", T)
    end
end

function KeyValue(bucket::String; connection::NATS.Connection = NATS.connection(:default))
    KeyValue{String}(bucket::String; connection)
end

function keyvalue_create(bucket::String; connection::NATS.Connection = NATS.connection(:default))
    stream_config = StreamConfiguration(
        name = "KV_$bucket",
        subjects = ["\$KV.$bucket.>"],
        allow_rollup_hdrs = true,
        deny_delete = true,
        allow_direct = true,
        max_msgs_per_subject = 1,
        discard = :new;
    )
    create(connection, stream_config)
end

function keyvalue_delete(bucket::String; connection::NATS.Connection = NATS.connection(:default))
    delete(connection, "KV_$bucket")
end

function keyvalue_names(; connection::NATS.Connection = NATS.connection(:default))
    map(stream_names(; subject = "\$KV.>", connection)) do sn
        replace(sn, r"^KV_"=>"")
    end
end

function keyvalue_list(; connection::NATS.Connection = NATS.connection(:default))
    stream_list(; subject = "\$KV.>", connection)
end

function validate_key(key::String)
    isempty(key) && error("Key is an empty string.")
    first(key) == '.' && error("Key \"$key\" starts with '.'")
    last(key) == '.' && error("Key \"$key\" ends with '.'")
    for c in key
        is_valid = isdigit(c) || isletter(c) || c in [ '-', '/', '_', '=', '.' ]
        !is_valid && error("Key \"$key\" contains invalid character '$c'.")
    end
    true
end

function setindex!(kv::KeyValue, value, key::String)
    validate_key(key)
    ack = JetStream.publish_with_ack(connection(kv), "\$KV.$(kv.bucket).$key", value)
    # TODO: validate puback
    kv
end

function setindex!(kv::KeyValue, value, key::Tuple{String, UInt64})
    key, revision = key
    validate_key(key)
    hdrs = ["Nats-Expected-Last-Subject-Sequence" => string(revision)]
    ack = publish(connection(kv), "\$KV.$(kv.bucket).$key", (value, hdrs))
    if ack.seq == 0
        error("Update failed, seq do not match. Please retry.")
    end
    # TODO: validate puback
    kv
end

const KV_REVISION_LATEST = 0

#  revision::UInt64 = KV_REVISION_LATEST
function getindex(kv::KeyValue, key::String, revision = KV_REVISION_LATEST)
    validate_key(key)
    msg = msg_get(connection(kv), "KV_$(kv.bucket)", "\$KV.$(kv.bucket).$key")
    status = NATS.statuscode(msg) 
    if status == 404
        throw(KeyError(key))
    elseif status > 399
        error("NATS error.") # TODO: show message.
    end
    op = NATS.headers(msg, "KV-Operation")
    if !isempty(op) && only(op) == "DEL"
        throw(KeyError(key))
    end
    seq = NATS.header(msg, "Nats-Sequence")
    ts = NATS.header(msg, "Nats-Time-Stamp")
    # KeyValueEntry(kv.bucket, key, NATS.payload(msg), parse(UInt64, seq), NanoDate(ts), 0, :none)
    convert(kv.value_type, msg)
end

function empty!(kv::KeyValue)
    # hdrs = [ "KV-Operation" => "PURGE" ]
    # ack = publish("\$KV.$(kv.bucket)", (nothing, hdrs); connection = kv.connection)
    purge(connection(kv), kv.stream_name)
end

function delete!(kv::KeyValue, key::String)
    hdrs = [ "KV-Operation" => "DEL" ]
    ack = publish("\$KV.$(kv.bucket).$key", (nothing, hdrs); connection = connection(kv))
end

function iterate(kv::KeyValue)
    cons = consumer_create("KV_$(kv.bucket)"; connection = connection(kv))
    # msg = next("KV_$(kv.bucket)", cons; connection = kv.connection, timer = Timer(1))
    msg = NATS.request(connection(kv), 1, "\$JS.API.CONSUMER.MSG.NEXT.KV_$(kv.bucket).$cons", "{\"no_wait\": true}")
    # @show msg
    msg = only(msg)
    NATS.statuscode(msg) == 404 && return nothing
    key = replace(msg.subject, "\$KV.$(kv.bucket)." => "")
    value = convert(kv.value_type, msg)
    (key => value, cons)
end

# function convert(::Type{KeyValueEntry}, msg::NATS.Msg)
#     spl = split(msg.reply_to, ".")
#     _1, _2, stream, cons, s1, seq, s3, nanos, rem = spl

#     KeyValueEntry(stream, msg.subject, NATS.payload(msg), parse(UInt64, seq), unixmillis2nanodate(parse(Int128, nanos)), 0, :none)
# end

function iterate(kv::KeyValue, cons)
    # msg = next("KV_$(kv.bucket)", cons; connection = kv.connection, timer = Timer(1))
    msg = NATS.request(connection(kv), "\$JS.API.CONSUMER.MSG.NEXT.KV_$(kv.bucket).$cons", "{\"no_wait\": true}", 1; timer = Timer(0.5))
    if isempty(msg)
        @error "Consumer disapeared."
        return nothing
    end
    # @show msg
    msg = only(msg)
    NATS.statuscode(msg) == 404 && return nothing
    key = replace(msg.subject, "\$KV.$(kv.bucket)." => "")
    value = convert(kv.value_type, msg)
    (key => value, cons)
end

function length(kv::KeyValue)
    consumer = consumer_create("KV_$(kv.bucket)"; connection = connection(kv))
    replies = NATS.request(connection(kv), "\$JS.API.CONSUMER.MSG.NEXT.KV_$(kv.bucket).$consumer", "{\"no_wait\": true}", 1)
    if isempty(replies)
        0
    else
        msg = only(replies)
        NATS.statuscode(msg) == 404 && return 0
        remaining = last(split(msg.reply_to, "."))
        parse(Int64, remaining) + 1
    end
end

function watch(f, kv::KeyValue, key::String = ALL_KEYS; kw...) 

end

function watch(kv::KeyValue, key::String = ALL_KEYS; kw...)::Channel{KeyValueEntry}

end

function history(kv::KeyValue, key::String)::Vector{KeyValueEntry}

end

function bucket(kv::KeyValue)
    kv.bucket
end

function kv_status()

end

# https://github.com/JuliaLang/julia/issues/25941

# get!, get,  getindex, haskey, setindex!, pairs, keys, values, delete!
# additionally: history(kventry::KeyValueEntry), get(; revision = nothing)
