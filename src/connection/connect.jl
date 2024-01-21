
function connect(url; options...)
    nc = NATS.connect(url; optins...)
end

struct JetStreamData
    connection::NATS.Connection
    allow_direct_streams::Dict{String, Bool} # Cache for streams with direct msg access.
end

function jetstream(connection::NATS.Connection)
    
end
