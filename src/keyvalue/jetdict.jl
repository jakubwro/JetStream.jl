

struct JetEntry{T}
    bucket::String                # Bucket is the bucket the data was loaded from.
    key::String                   # Key is the key that was retrieved.
    value::Union{T, Nothing}      # Value is the retrieved value, can be `nothing` if op is DEL or client opted headers only.
    revision::UInt64              # Revision is a unique sequence for this value.
    created::NanoDate             # Created is the time the data was put in the bucket.
    delta::UInt64                 # Delta is distance from the latest value.
    operation::Symbol             # Operation can be `:put`, `:delete` or `:purge`.
end

struct JetDict{T}
    connection::NATS.Connection
    bucket::String
    stream_info::StreamInfo
    T::DataType
    revisions::ScopedValue{Dict{String, UInt64}}
end

function JetDict{T}(connection::NATS.Connection, bucket::String) where T
    NATS.find_msg_conversion_or_throw(T)
    NATS.find_data_conversion_or_throw(T)
    stream = streaminfo(connection, "KV_$bucket")
    if isnothing(stream)
        stream = create_or_update_kv(connection, )
    end
    JetDict{T}(connection, bucket, stream_info, T)
end

const DEFAULT_JETSTREAM_OPTIMISTIC_RETRIES = 3

function with_optimistic_concurrency(f, kv::JetDict; retry = true)
    with(kv.revisions => Dict{String, UInt64}()) do
        for _ in 1:DEFAULT_JETSTREAM_OPTIMISTIC_RETRIES
            try
                f()
            catch err
                if err isa ApiError && err.err_code == 10071
                    @warn "Key update clash."
                    retry && continue
                else
                    rethrow()
                end
            end
        end
    end
end

function history(jetdict::JetDict)::Vector{JetEntry}

end
