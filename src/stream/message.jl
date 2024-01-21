
function stream_message_get(connection::NATS.Connection, stream::StreamInfo, subject)
    if stream.config.allow_direct
        replies = NATS.request(connection, 1, "\$JS.API.DIRECT.GET.$(stream.config.name)", "{\"last_by_subj\": \"$subject\"}")
        isempty(replies) && error("No replies.")
        m = first(replies)
        # @show NATS.headers_str(m) m.subject m.reply_to
        #TODO: structured NATSError
        m
    else
        replies = NATS.request(connection, "\$JS.API.STREAM.MSG.GET.$stream_name", "{\"last_by_subj\": \"\$KV.asdf.$subject\"}", 1)
        isempty(replies) && error("No replies.")
        first(replies)
    end
end

function stream_message_delete(stream_name::String, seq::UInt64; connection = NATS.connection(:default))
    replies = NATS.request(connection, "\$JS.API.STREAM.MSG.DELETE.$stream_name", "{\"seq\": \"\$KV.asdf.$subject\"}", 1)
    isempty(replies) && error("No replies.")
    first(replies)
end
