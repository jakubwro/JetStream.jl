using Test
using NATS
using JetStream
using Random

@testset "Work queue." begin

    connection = JetStream.connect()
    
    rng = MersenneTwister()

    stream_name = randstring(rng, 10)
    subject_prefix = randstring(rng, 4)

    stream_config = JetStream.StreamConfiguration(
        name = stream_name,
        description = "Work queue stream.",
        subjects = ["$subject_prefix.*"],
        retention = :workqueue,
        storage = :memory
    )
    stream_info = JetStream.create(connection, stream_config)
    @test stream_info isa JetStream.StreamInfo

    consumer_config = JetStream.ConsumerConfiguration(
        filter_subjects=["$subject_prefix.*"],
        ack_policy = :explicit,
        name ="workqueue_consumer"
    )

    consumer = JetStream.create(connection, consumer_config, stream_info)

    n_workers = 3
    n_publications = 100
    results = Channel(n_publications)
    cond = Channel()

    for i in 1:n_workers
        worker_task = Threads.@spawn :default JetStream.worker(stream_name, "workqueue_consumer"; connection) do msg
            put!(results, (i, msg))
            if Base.n_avail(results) == n_publications
                close(cond)
            end
        end
        errormonitor(worker_task)
    end
    
    for i in 1:n_publications
        NATS.publish(connection, "$subject_prefix.task", "Task $i")
    end

    try take!(cond) catch end
    close(results)
    res = collect(results)
    wa = first.(res)
    msgs = last.(res)


    for i in 1:n_workers
        @test i in wa
    end

    payloads = NATS.payload.(msgs)

    for i in 1:n_publications
        @test "Task $i" in payloads
    end
end
