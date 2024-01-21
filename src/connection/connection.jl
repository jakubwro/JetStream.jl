
struct Context
    nats_connection::NATS.Connection

    function Connection(nc::NATS.Connection)
        new(nc)
    end
end
