using Test
using NATS
using JetStream
using Random

@testset "Create stream and delete stream." begin
    connection = NATS.connect()
    did_create = stream_create(;
        name = "SOME_STREAM",
        description = "SOME_STREAM stream",
        subjects = ["SOME_STREAM.*"],
        retention = :workqueue,
        storage = :memory,
        connection = connection)
    @test did_create
    names = JetStream.stream_names(; connection, subject = "SOME_STREAM.*")
    @test "SOME_STREAM" in names
    @test length(names) == 1
    JetStream.stream_delete(; connection, name = "SOME_STREAM")
    names = JetStream.stream_names(; connection)
    @test !("SOME_STREAM" in names)
end

@testset "Stream names handling error." begin
    connection = NATS.connect()
    @test_throws ErrorException JetStream.stream_names(; connection, timer = Timer(0))

    response = JSON3.read("""{"error": {"code": 400, "description": "failed"}}""")
    @test_throws JetStream.ApiError JetStream.throw_on_api_error(response)
end

@testset "Invalid stream name." begin
    connection = NATS.connect()
    @test_throws ErrorException JetStream.stream_create(;
        name = "SOME*STREAM",
        description = "Stream with invalid name",
        subjects = ["SOME_STREAM.*"],
        connection = connection)
end

@testset "Create stream, publish and subscribe." begin
    connection = NATS.connect()
    
    stream_name = randstring(10)
    subject_prefix = randstring(4)

    did_create = stream_create(
        connection = connection,
        name = stream_name,
        description = "Test generated stream.",
        subjects = ["$subject_prefix.*"],
        retention = :limits,
        storage = :memory)

    @test did_create

    NATS.publish("$subject_prefix.test", "Publication 1"; connection)
    NATS.publish("$subject_prefix.test", "Publication 2"; connection)
    NATS.publish("$subject_prefix.test", "Publication 3"; connection)

    consumer = JetStream.consumer_create(
        stream_name;
        connection,
        filter_subjects=["$subject_prefix.*"],
        ack_policy = :explicit,
        name ="c1")
    
    msg = JetStream.next(stream_name, consumer; connection)
    @test msg isa NATS.Message

    msg = JetStream.next(stream_name, consumer; connection)
    @test msg isa NATS.Message

    msg = JetStream.next(stream_name, consumer; connection)
    @test msg isa NATS.Message

    @test_throws ErrorException JetStream.next(stream_name, consumer; connection)
end

@testset "Ack" begin
    connection = NATS.connect()
    no_reply_to_msg = NATS.Msg("FOO.BAR", "9", nothing, 11, "Hello World")
    @test_throws ErrorException JetStream.ack(no_reply_to_msg; connection)
    @test_throws ErrorException JetStream.nak(no_reply_to_msg; connection)

    msg = NATS.Msg("FOO.BAR", "9", "ack_subject", 11, "Hello World")
    c = Channel(10)
    sub = subscribe("ack_subject"; connection) do msg
        put!(c, msg)
    end
    JetStream.ack(msg; connection)
    JetStream.nak(msg; connection)
    sleep(0.5)
    unsubscribe(sub; connection)
    close(c)
    acks = collect(c)
    @test length(acks) == 2
    @test "-NAK" in payload.(acks)
end


