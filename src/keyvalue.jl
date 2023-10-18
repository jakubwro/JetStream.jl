
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

struct KeyValue <: AbstractDict{String, KeyValueEntry}
    connection::NATS.Connection
    bucket::String
    stream_name::String
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

function keyvalue(bucket::String; connection::NATS.Connection = NATS.connection(:default))
    stream_info("KV_$bucket"; connection)
    KeyValue(connection, bucket, "KV_$bucket")
end

function keyvalue_delete(bucket::String; connection::NATS.Connection = NATS.connection(:default))
    stream_delete(name = "KV_$bucket"; connection)
end

function keyvalue_names()

end

function keyvalue_list()

end

function setindex!(kv::KeyValue, key::String, value)
    ack = publish("\$KV.$(kv.bucket).$key", value; connection = kv.connection)
    # TODO: validate puback
    kv
end

const KV_REVISION_LATEST = 0

#  revision::UInt64 = KV_REVISION_LATEST
function getindex(kv::KeyValue, key::String)
    msg = stream_msg_get_direct("KV_$(kv.bucket)", "\$KV.$(kv.bucket).$key"; connection = kv.connection)
    op = NATS.headers(msg, "KV-Operation")
    if !isempty(op) && only(op) == "DEL"
        throw(KeyError(key))
    end
    seq = NATS.header(msg, "Nats-Sequence")
    ts = NATS.header(msg, "Nats-Time-Stamp")
    KeyValueEntry(kv.bucket, key, NATS.payload(msg), parse(UInt64, seq), NanoDate(ts), 0, :none)
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
