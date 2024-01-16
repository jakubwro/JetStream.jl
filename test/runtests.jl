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
        nc = JetStream.connect()
        @assert nc.status == NATS.CONNECTED
        @info "JetStream avaliable, running connected tests."
        true
    catch err
        @info "JetStream unavailable, skipping connected tests."  err
        false
    end
end

if have_nats()
    include("stream.jl")
    include("keyvalue.jl")
    include("worker.jl")
end