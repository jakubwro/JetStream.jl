
function check_x(s, e)
    @show e
    true
end

function publish(subject, data; delays = [1,1,1])
    resp = NATS.request(subject, data, 1)

    if isempty(resp)
        error("No `ack` received.")
        # TODO: add hint: For streams that have `no_ack` enabled use `NATS.publish` instead of `JetStream.publish`
    end

    msg = only(resp)

    if NATS.statuscode(msg) == 503
        error("No responders.") # TODO: retry like in delays
        for delay in delays
            sleep(delay)
            resp = NATS.request(subject, data, 1)
            msg = only(resp)
            NATS.statuscode(msg) == 503 || break
        end
    end

    JSON3.read(NATS.payload(msg), PubAck)
end