

function subscribe(f, connection, subject)
    @show connection
    @show subject
    subject_streams = streams(connection, subject)
    if isempty(subject_streams)
        error("No stream found for subject `$subject`")
    end
    if length(subject_streams) > 1
        error("Multiple streams found")
    end
    stream = only(subject_streams)
    name = randstring(20)
    deliver_subject = randstring(8)
    idle_heartbeat = 1000 * 1000 * 1000 * 3 # 300 ms
    consumer_config = ConsumerConfiguration(;name, deliver_subject)
    consumer = create(connection, consumer_config, stream)
    f_typed = NATS._fast_call(f)
    sub = NATS.subscribe(connection, deliver_subject) do msg
        if NATS.statuscode(msg) == 100
            @info "heartbeat"
        else
            f_typed(msg)
        end
    end
    sub, consumer
end

function unsubscribe(connection, subscription::Tuple{NATS.Sub, JetStream.ConsumerInfo})
    sub, cons = subscription
    NATS.unsubscribe(connection, sub)
    delete(connection, cons)
end