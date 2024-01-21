using Test
using NATS
using JetStream
using Random

@testset "Create stream and delete stream." begin
    connection = JetStream.connect()
    stream_config = StreamConfiguration(
        name = "SOME_STREAM",
        description = "SOME_STREAM stream",
        subjects = ["SOME_STREAM.*"],
        retention = :workqueue,  
        storage = :memory,
    )
    stream_info = JetStream.stream_create(connection, stream_config)

    @test stream_info isa JetStream.StreamInfo
    names = JetStream.stream_names(connection, "SOME_STREAM.*")
    @test "SOME_STREAM" in names
    @test length(names) == 1
    JetStream.stream_delete(connection, stream_info)
    names = JetStream.stream_names(connection, "SOME_STREAM.*")
    @test !("SOME_STREAM" in names)
end

# @testset "Stream names handling error." begin
#     connection = NATS.connect()
#     # @test_throws ErrorException JetStream.stream_names(; connection, timer = Timer(0))

#     response = JSON3.read("""{"error": {"code": 400, "description": "failed"}}""")
#     @test_throws JetStream.ApiError JetStream.throw_on_api_error(response)
# end

@testset "Invalid stream name." begin
    connection = JetStream.connect()
    stream_config = StreamConfiguration(
        name = "SOME*STREAM",
        description = "Stream with invalid name",
        subjects = ["SOME_STREAM.*"],
    )
    @test_throws ErrorException JetStream.stream_create(connection, stream_config)
end

@testset "Create stream, publish and subscribe." begin
    connection = JetStream.connect()
    
    stream_name = randstring(10)
    subject_prefix = randstring(4)

    stream_config = StreamConfiguration(
        name = stream_name,
        description = "Test generated stream.",
        subjects = ["$subject_prefix.*"],
        retention = :limits,
        storage = :memory,
        metadata = Dict("asdf" => "aaaa")
    )
    stream_info = JetStream.stream_create(connection, stream_config)
    @test stream_info isa JetStream.StreamInfo

    # TODO: fix this
    # @test_throws ErrorException JetStream.create(connection, stream_config)

    NATS.publish(connection, "$subject_prefix.test", "Publication 1")
    NATS.publish(connection, "$subject_prefix.test", "Publication 2")
    NATS.publish(connection, "$subject_prefix.test", "Publication 3")

    consumer_config = JetStream.ConsumerConfiguration(
        filter_subjects=["$subject_prefix.*"],
        ack_policy = :explicit,
        name ="c1"
    )
    consumer = JetStream.consumer_create(connection, consumer_config, stream_info)

    for i in 1:3
        msg = JetStream.consumer_next(connection, consumer)
        @test msg isa NATS.Msg
    end
    #TODO: fix
    # @test_throws ErrorException @show JetStream.next(connection, consumer)
end

uint8_vec(s::String) = convert.(UInt8, collect(s))

@testset "Ack" begin
    connection = JetStream.connect()
    no_reply_to_msg = NATS.Msg("FOO.BAR", "9", nothing, 0, uint8_vec("Hello World"))
    @test_throws ErrorException JetStream.message_ack(no_reply_to_msg; connection)
    @test_throws ErrorException JetStream.message_nak(no_reply_to_msg; connection)

    msg = NATS.Msg("FOO.BAR", "9", "ack_subject", 0, uint8_vec("Hello World"))
    c = Channel(10)
    sub = NATS.subscribe(connection, "ack_subject") do msg
        put!(c, msg)
    end
    JetStream.message_ack(msg; connection)
    JetStream.message_nak(msg; connection)
    NATS.drain(connection, sub)
    close(c)
    acks = collect(c)
    @test length(acks) == 2
    @test "-NAK" in NATS.payload.(acks)
end


