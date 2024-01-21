
function _try_request(subject, data; connection)
    replies = NATS.request(connection, 1, subject, data)
    isempty(replies) && error("No `ack` received.")
    only(replies)
end

function stream_publish(connection::NATS.Connection, subject, data; delays = [1,1,1])
    ack_msg = _try_request(subject, data; connection)
    if NATS.statuscode(ack_msg) == 503
        for delay in delays
            sleep(delay)
            ack_msg == _try_request(subject, data; connection)
            NATS.statuscode(ack_msg) == 503 || break
        end
    end

    if NATS.statuscode(ack_msg) >= 400
        error("No ack") # TODO: better error handling
    end

    JSON3.read(NATS.payload(ack_msg), PubAck)
end
