using Test
using JSON3
using Sockets

using NATS
using JetStream

@info "Running with $(Threads.nthreads()) threads."

function have_nats()
    try
        Sockets.getaddrinfo(NATS.NATS_HOST)
        nc = NATS.connect()
        sleep(5)
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
end