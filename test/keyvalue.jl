@testset "Key value - 100 keys" begin
    connection = NATS.connect()

    JetStream.keyvalue_create("test_kv"; connection)
    kv = JetStream.keyvalue("test_kv"; connection)

    @time @sync for i in 1:10000
        @async kv["key_$i"] = "value_$i"
    end

    other_conn = NATS.connect()
    kv = JetStream.keyvalue("test_kv"; connection = other_conn)

    for i in 1:100
        @test kv["key_$i"].value == "value_$i"
    end
end
