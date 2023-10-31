@testset "Key value - 100 keys" begin
    connection = NATS.connect()
    kv = JetStream.KeyValue("test_kv"; connection)
    @time @sync for i in 1:100
        @async kv["key_$i"] = "value_$i"
    end

    other_conn = NATS.connect()
    kv = JetStream.KeyValue("test_kv"; connection = other_conn)
    for i in 1:100
        @test kv["key_$i"] == "value_$i"
    end
end

@testset "Create and delete KV bucket" begin
    connection = NATS.connect()
    bucket = randstring(10)
    kv = JetStream.KeyValue(bucket; connection)
    @test_throws KeyError kv["some_key"]
    kv["some_key"] = "some_value"
    @test kv["some_key"] == "some_value"
    empty!(kv)
    @test_throws KeyError kv["some_key"]
    JetStream.keyvalue_delete(bucket; connection)
    @test_throws "stream not found" first(kv)
end