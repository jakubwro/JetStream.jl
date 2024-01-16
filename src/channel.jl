# struct JetStreamChannel{T} <: AbstractChannel{T}
#     connection::NATS.Connection
#     name::String
#     size::UInt64
# end

# # use two streams, one for write, second for read

# function JetStreamChannel(name::String; connection::NATS.Connection = NATS.connection(:default))
#     # in case of 0 size use 1 size and block until consumer proceeds

#     # create or open a stream with workqueue retention
#     stream_create(;
#         name = "$(name)_out",
#         subjects = ["julia_channel.$(name)_out"],
#         retention = :limits,
#         connection)
#     stream_create(;
#         name = "$(name)_in",
#         subjects = ["julia_channel.$(name)_in"],
#         retention = :workqueue,
#         republish = Republish("julia_channel.$(name)_in", "julia_channel.$(name)_out", false),
#         connection)
#     consumer_create(
#         "$(name)_out";
#         connection,
#         ack_policy = :explicit,
#         name ="channel_consumer",
#         durable_name = "channel_consumer")

#     JetStreamChannel{String}(connection, name)
# end

# function put!(ch::JetStreamChannel, data)
#     isopen(ch) || error("Channel is closed.")
#     JetStream.publish("julia_channel.$(ch.name)_in", data)
# end

# function take!(ch::JetStreamChannel)
#     while true
#         try
#             msg = next("$(ch.name)_out", "channel_consumer"; connection = ch.connection)
#             ack(msg; connection = ch.connection)
#             return msg
#         catch
#         end
#     end
# end

# # function close(ch::JetStreamChannel)
# #     # put metadata
# #     stream_delete(connection = ch.connection, name = "$(ch.name)_in")
# # end

# # function isopen(ch::JetStreamChannel)
# #     try
# #         JetStream.stream_info("$(ch.name)_in")
# #         true
# #     catch err
# #         if err isa ApiError && err.code == 404
# #             false
# #         else
# #             rethrow()
# #         end
# #     end
# # end
