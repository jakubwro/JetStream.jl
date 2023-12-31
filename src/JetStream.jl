module JetStream

using Dates
using NanoDates
using StructTypes
using Random
using JSON3

import NATS
using NATS: isdrained

import Base: show, showerror
import Base: setindex!, getindex, empty!, delete!, iterate, length

abstract type JetStreamPayload end

const STREAM_RETENTION_OPTIONS       = [:limits, :interest, :workqueue]
const STREAM_STORAGE_OPTIONS         = [:file, :memory]
const STREAM_COMPRESSION_OPTIONS     = [:none, :s2]
const CONSUMER_ACK_POLICY_OPTIONS    = [:none, :all, :explicit]
const CONSUMER_REPLAY_POLICY_OPTIONS = [:instant, :original]

include("structs.jl")
include("errors.jl")
include("validate.jl")
include("stream.jl")
include("consumer.jl")
include("keyvalue.jl")
include("show.jl")
include("convert.jl")
include("worker.jl")
include("publish.jl")
include("init.jl")

export PubAck, StreamConfiguration, stream_create, limits, interest, workqueue, memory, file, NATS, publish

end
