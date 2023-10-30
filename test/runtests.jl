using Test
using JSON3
using Sockets
using Random

using NATS
using JetStream

@info "Running with $(Threads.nthreads()) threads."

function have_nats()
    try
        Sockets.getaddrinfo(get(ENV, "NATS_HOST", "localhost"))
        nc = NATS.connect()
        sleep(10)
        @assert nc.status == NATS.CONNECTED
        @info "NATS avaliable, running connected tests."
        true
    catch err
        @info "NATS unavailable, skipping connected tests."  err
        false
    end
end

if have_nats()
    include("jetstream.jl")
    include("worker.jl")
    include("keyvalue.jl")
end