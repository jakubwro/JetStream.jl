
const KEY_VALUE_OPERATIONS = [:none, :put, :delete, :purge]

const MAX_HISTORY    = 64
const ALL_KEYS       = ">"
const LATEST_REVISION = UInt(0)

struct KeyValueEntry{TValue}
    # Bucket is the bucket the data was loaded from.
    bucket::String
    # Key is the key that was retrieved.
    key::String
    # Value is the retrieved value.
    value::Union{TValue, Nothing}
    # Revision is a unique sequence for this value.
    revision::UInt64
    # Created is the time the data was put in the bucket.
    created::NanoDate
    # Delta is distance from the latest value.
    delta::UInt64
    # Operation returns Put or Delete or Purge.
    operation::Symbol
end

function show(io::IO, entry::KeyValueEntry)
    print(io, "$(entry.key) => $(entry.value)")
end

function isdeleted(entry::KeyValueEntry)
    entry.operation == :del || entry.operation == :purge
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
    ack = publish_with_ack(connection(kv), "\$KV.$(kv.bucket).$key", (nothing, hdrs))
end

function _kv_op(msg::NATS.Msg)
    hdrs = String(@view msg.payload[begin:msg.headers_length])
    range = findfirst("KV-Operation", hdrs)
    isnothing(range) && return :none
    ending = findfirst("\r\n", hdrs[last(range):end])
    op = hdrs[(last(range) + 3):(last(range) + first(ending)-2)]
    if op == "DEL"
        :del
    elseif op == "PURGE"
        :purge
    else
        :unexpected
    end
end

function watch(f, kv::KeyValue; skip_deleted = false, all = true)::Tuple{NATS.Sub, ConsumerInfo}
    JetStream.subscribe(connection(kv), "\$KV.$(kv.bucket).>") do msg
        headers = NATS.headers(msg)
        keys = first.(headers)
        op = _kv_op(msg)
        value = if op == :del || op == :purge
                    nothing
                else
                    convert(kv.value_type, msg)
                end
        entry = KeyValueEntry{kv.value_type}(kv.bucket, msg.subject, value, 0, NanoDate(), 0, op)
        if !isdeleted(entry) || !skip_deleted
            f(entry)
        end
    end
end

function iterate(kv::KeyValue)
    unique_keys = Set{String}()
    consumer_config = ConsumerConfiguration(
        name = randstring(20)
    )
    consumer = create(connection(kv), consumer_config, "KV_$(kv.bucket)")
    msg = next(connection(kv), consumer, no_wait = true)
    if NATS.statuscode(msg) == 404
        # TODO: remove consumer?
        return nothing
    end
    key = replace(msg.subject, "\$KV.$(kv.bucket)." => "")
    value = convert(kv.value_type, msg)
    push!(unique_keys, key)
    (key => value, (consumer, unique_keys))
end

# function convert(::Type{KeyValueEntry}, msg::NATS.Msg)
#     spl = split(msg.reply_to, ".")
#     _1, _2, stream, cons, s1, seq, s3, nanos, rem = spl

#     KeyValueEntry(stream, msg.subject, NATS.payload(msg), parse(UInt64, seq), unixmillis2nanodate(parse(Int128, nanos)), 0, :none)
# end

# No way to get number of not deleted items fast, also kv can change during iteration.
IteratorSize(::KeyValue) = Base.SizeUnknown()
IteratorSize(::Base.KeySet{String, KeyValue{T}}) where {T} = Base.SizeUnknown()
IteratorSize(::Base.ValueIterator{JetStream.KeyValue{T}}) where {T} = Base.SizeUnknown()

function iterate(kv::KeyValue, (consumer, unique_keys))
    msg = next(connection(kv), consumer, no_wait = true)
    if NATS.statuscode(msg) == 404
        return nothing
    end
    key = replace(msg.subject, "\$KV.$(kv.bucket)." => "")
    op = _kv_op(msg)
    if key in unique_keys
        @warn "Key \"$key\" changed during iteration."
        # skip item
        iterate(kv, (consumer, unique_keys))
    elseif op == :del || op == :purge 
        # Item is deleted, continue.
        #TODO change cond order
        iterate(kv, (consumer, unique_keys))
    else
        value = convert(kv.value_type, msg)
        push!(unique_keys, key)
        (key => value, (consumer, unique_keys))
    end
end

function length(kv::KeyValue)
    # TODO: this is not reliable way to check length, it counts deleted items
    consumer_config = ConsumerConfiguration(
        name = randstring(20)
    )
    consumer = create(connection(kv), consumer_config, "KV_$(kv.bucket)")
    msg = next(connection(kv), consumer, no_wait = true)
    if NATS.statuscode(msg) == 404
        0
    else
        remaining = last(split(msg.reply_to, "."))
        parse(Int64, remaining) + 1
    end
end

# function watch(f, kv::KeyValue, key::String = ALL_KEYS; kw...) 

# end

# function watch(kv::KeyValue, key::String = ALL_KEYS; kw...)::Channel{KeyValueEntry}

# end

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
