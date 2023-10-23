
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
    created::NanoDate # DateTime
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

function KeyValue{T}(bucket::String; connection::NATS.Connection = NATS.connection(:default)) where T
    NATS.find_msg_conversion_or_throw(T)
    NATS.find_data_conversion_or_throw(T)
    try
        stream_info("KV_$bucket"; connection)
        KeyValue{T}(connection, bucket, "KV_$bucket", T)
    catch err
        if err isa ApiError && err.code == 404
            @info "KV $bucket does not exists, creating now."
            if keyvalue_create(bucket; connection)
                KeyValue{T}(connection, bucket, "KV_$bucket", T)
            else
                error("Cannot create KV $bucket.")
            end
        else
            rethrow()
        end
    end
end

function KeyValue(bucket::String; connection::NATS.Connection = NATS.connection(:default))
    KeyValue{String}(bucket::String; connection)
end

function keyvalue_create(bucket::String; connection::NATS.Connection = NATS.connection(:default))
    stream_create(
        name = "KV_$bucket",
        subjects = ["\$KV.$bucket.>"],
        allow_rollup_hdrs = true,
        deny_delete = true,
        allow_direct = true,
        max_msgs_per_subject = 1,
        discard = :new;
        connection)
end

function keyvalue_delete(bucket::String; connection::NATS.Connection = NATS.connection(:default))
    stream_delete(name = "KV_$bucket"; connection)
end

function keyvalue_names()

end

function keyvalue_list()

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
    ack = publish("\$KV.$(kv.bucket).$key", value; connection = kv.connection)
    @show ack
    # TODO: validate puback
    kv
end

function setindex!(kv::KeyValue, value, key::String, revision::UInt64)
    validate_key(key)
    hdrs = ["Nats-Expected-Last-Subject-Sequence" => string(revision)]
    ack = publish("\$KV.$(kv.bucket).$key", (value, hdrs); connection = kv.connection)
    @show ack
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
    msg = stream_msg_get_direct("KV_$(kv.bucket)", "\$KV.$(kv.bucket).$key"; connection = kv.connection)
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
    stream_purge(kv.stream_name; connection = kv.connection)
end

function delete!(kv::KeyValue, key::String)
    hdrs = [ "KV-Operation" => "DEL" ]
    ack = publish("\$KV.$(kv.bucket).$key", (nothing, hdrs); connection = kv.connection)
end

function iterate(kv::KeyValue)
    cons = consumer_create("KV_$(kv.bucket)"; connection = kv.connection)
    # msg = next("KV_$(kv.bucket)", cons; connection = kv.connection, timer = Timer(1))
    msg = NATS.request("\$JS.API.CONSUMER.MSG.NEXT.KV_$(kv.bucket).$cons", "{\"no_wait\": true}", 1; connection = kv.connection)
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
    msg = NATS.request("\$JS.API.CONSUMER.MSG.NEXT.KV_$(kv.bucket).$cons", "{\"no_wait\": true}", 1; connection = kv.connection, timer = Timer(0.5))
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
    consumer = consumer_create("KV_$(kv.bucket)"; connection = kv.connection)
    replies = NATS.request("\$JS.API.CONSUMER.MSG.NEXT.KV_$(kv.bucket).$consumer", "{\"no_wait\": true}", 1; connection = kv.connection)
    if isempty(replies)
        0
    else
        msg = only(replies)
        NATS.statuscode(msg) == 404 && return 0
        remaining = last(split(msg.reply_to, "."))
        parse(Int64, remaining) + 1
    end
end

function kv_watch(kv::Any, key::String = nothing; kw...)::Channel{KeyValueEntry} # better use do

end

function kv_keys(kv::Any) # keys

end


function kv_history(kv::Any, key::String)

end

function bucket(kv::KeyValue)
    kv.bucket
end

function kv_status()

end

# https://github.com/JuliaLang/julia/issues/25941

# get!, get,  getindex, haskey, setindex!, pairs, keys, values, delete!
# additionally: history(kventry::KeyValueEntry), get(; revision = nothing)
