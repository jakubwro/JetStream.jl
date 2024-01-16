"""
$SIGNATURES

Create NATS connection with message fallback handler specific to JetStream.

See also [`NATS.connect`](@ref).
"""
function connect(url = get(ENV, "NATS_CONNECT_URL", NATS.DEFAULT_CONNECT_URL); options...)
    if haskey(options, :retry_on_init_fail)
        error("`retry_on_init_fail` option not supperted for jetstream connections")
    end
    nc = NATS.connect(url; options...)
    @info "JetStream"
    conn_info = NATS.info(nc)
    if isnothing(conn_info.jetstream) || conn_info.jetstream == false
        error("Server `$(nc.url)` has no JetStream enabled.")
        drain(nc)
    end
    NATS.install_fallback_handler(jetstream_fallback_handler)
    nc
end
