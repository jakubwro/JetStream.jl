module JetStream

using Dates
using StructTypes
using Random
using JSON3

import NATS
using NATS: isdrained

abstract type JetStreamPayload end

@enum SteramRetentionPolicy limits interest workqueue
@enum StreamStorage file memory
@enum StreamCompression none s2
@enum AckPolicy all explicit
@enum ConsumerReplayPolicy instant original

include("structs.jl")
include("validate.jl")
include("stream.jl")
include("consumer.jl")
include("keyvalue.jl")
include("show.jl")
include("convert.jl")
include("worker.jl")

export StreamConfiguration, stream_create, limits, interest, workqueue, memory, file, NATS

end
