module JetStream

using Dates
using NanoDates
using StructTypes
using Random
using JSON3
using DocStringExtensions
using ScopedValues

import NATS

import Base: show, showerror
import Base: setindex!, getindex, empty!, delete!, iterate, length
import Base: IteratorSize

abstract type JetStreamPayload end

const STREAM_RETENTION_OPTIONS       = [:limits, :interest, :workqueue]
const STREAM_STORAGE_OPTIONS         = [:file, :memory]
const STREAM_COMPRESSION_OPTIONS     = [:none, :s2]
const CONSUMER_ACK_POLICY_OPTIONS    = [:none, :all, :explicit]
const CONSUMER_REPLAY_POLICY_OPTIONS = [:instant, :original]

include("connection.jl")
include("api/api.jl")
include("errors.jl")
include("validate.jl")
include("stream/stream.jl")
include("consumer/consumer.jl")
include("keyvalue.jl")
include("show.jl")
include("convert.jl")
include("worker.jl")
include("pubsub/pubsub.jl")
# include("publish.jl")
# include("subscribe.jl")
include("init.jl")
include("channel.jl")


export PubAck, StreamConfiguration, stream_create, limits, interest, workqueue, memory, file, NATS, publish

end
