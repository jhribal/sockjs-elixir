defmodule Sockjs.Action do

	alias Sockjs.Http
	alias Sockjs.Service
  alias Sockjs.Util
  alias Sockjs.Json
  alias Sockjs.Handler
  
	@iframe """
	<!DOCTYPE html>
	<html>
		<head>
  			<meta http-equiv=\"X-UA-Compatible\" content=\"IE=edge\" />
  			<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" />
  			<script>
    			document.domain = document.domain;
    			_sockjs_onload = function(){SockJS.bootstrap_iframe();};
  			</script>
  			<script src=\"~s\"></script>
		</head>
		<body>
  			<h2>Don't panic!</h2>
  			<p>This is a SockJS hidden iframe. It's used for cross domain magic.</p>
		</body>
	</html>
	"""

	@iframe_htmlfile """
	<!doctype html>
	<html>
		<head>
  			<meta http-equiv=\"X-UA-Compatible\" content=\"IE=edge\" />
  			<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" />
		</head>
		<body>
			<h2>Don't panic!</h2>
  			<script>
    		document.domain = document.domain;
    		var c = parent.~s;
    		c.start();
    		function p(d) {c.message(d);};
    		window.onload = function() {c.stop();};
  			</script>
  	"""

	def welcome_screen(req, headers, _service) do
      h = [{"Content-Type", "text/plain; charset=UTF-8"}]
    	Http.reply(200, h ++ headers, "Welcome to SockJS!\n", req)
  end

	def options(req, headers, _service) do
    	Http.reply(204, headers, "", req)
  end

	def iframe(req, headers, %Service{sockjs_url: sockjsUrl}) do
    	iFrame = :io_lib.format(@iframe, [sockjsUrl])
    	md5 = "\"" ++ :erlang.binary_to_list(:base64.encode(:erlang.md5(iFrame))) ++ "\""
    	{h, req} = Http.header(:'if-none-match', req)
    	case h do
        	^md5 -> Http.reply(304, headers, "", req)
        	_   -> Http.reply(
                 200, [{"Content-Type", "text/html; charset=UTF-8"},
                       {"ETag", md5}] ++ headers, iFrame, req)
    	end
  end

	def info_test(req, headers, %Service{websocket: websocket,
                                 		 cookie_needed: cookieNeeded}) do
      IO.puts "starting info test..."
    	i = %{websocket: websocket,
            cookie_needed: cookieNeeded,
            origins: ["*:*"],
            entropy: Util.rand32()}
      IO.inspect i
    	d = Json.encode(i)
      IO.puts "after json encode..."
    	h = [{"Content-Type", "application/json; charset=UTF-8"}]
      IO.puts "ending info test..."
    	Http.reply(200, h ++ headers, d, req)
  end

	def xhr_polling(req, headers, service, session) do
    	req = chunk_start(req, headers)
    	reply_loop(req, session, 1, &fmt_xhr/1, service)
  end

	def xhr_streaming(req, headers, %Service{response_limit: responseLimit} = service,
              session) do
    	req = chunk_start(req, headers)
    	# IE requires 2KB prefix:
    	# http://blogs.msdn.com/b/ieinternals/archive/2010/04/06/comet-streaming-in-internet-explorer-with-xmlhttprequest-and-xdomainrequest.aspx
    	req = chunk(req, :erlang.list_to_binary(:string.copies("h", 2048)), &fmt_xhr/1)
    	reply_loop(req, session, responseLimit, &fmt_xhr/1, service)
  end

	def eventsource(req, headers, %Service{response_limit: responseLimit} = service, sessionId) do
    	req = chunk_start(req, headers, "text/event-stream; charset=UTF-8")
    	req = chunk(req, <<"\r\n">>)
    	reply_loop(req, sessionId, responseLimit, &fmt_eventsource/1, service)
  end

	def htmlfile(req, headers, %Service{response_limit: responseLimit} = service, sessionId) do
    	s = fn (req1, cb) ->
                req1 = chunk_start(req1, headers, "text/html; charset=UTF-8")
                iFrame = :erlang.iolist_to_binary(:io_lib.format(@iframe_htmlfile, [cb]))
                # Safari needs at least 1024 bytes to parse the
                # website. Relevant:
                # http://code.google.com/p/browsersec/wiki/Part2#Survey_of_content_sniffing_behaviors
                padding = :string.copies(" ", 1024 - :erlang.size(iFrame))
                req1 = chunk(req1, [iFrame, padding, <<"\r\n\r\n">>])
                reply_loop(req1, sessionId, responseLimit, &fmt_htmlfile/1, service)
        	end
    	verify_callback(req, s)
  end

	def jsonp(req, headers, service, sessionId) do
    	s = fn (req1, cb) ->
                req1 = chunk_start(req1, headers)
                reply_loop(req1, sessionId, 1,
                           fn (body) -> fmt_jsonp(body, cb) end, service)
        	end
    	verify_callback(req, s)
	end

	defp verify_callback(req, success) do
    	{cb, req} = Http.callback(req)
    	case cb do
        	:undefined ->
            	Http.reply(500, [], "\"callback\" parameter required", req)
        	_ ->
            	success.(req, cb)
    	end
  end

	def xhr_send(req, headers, _service, session) do
    	{body, req} = Http.body(req)
    	case handle_recv(req, body, session) do
        	{:error, req} -> req
        	:ok ->
            	h = [{"content-type", "text/plain; charset=UTF-8"}]
            	Http.reply(204, h ++ headers, "", req)
    	end
  end

	def jsonp_send(req, headers, _service, session) do
    	{body, req} = Http.body_qs(req)
    	case handle_recv(req, body, session) do
        	{:error, req} -> req
        	:ok ->
            	h = [{"content-type", "text/plain; charset=UTF-8"}]
            	Http.reply(200, h ++ headers, "ok", req)
    	end
  end

  defp handle_recv(req, body, session) do
   		case body do
        	_any when body !== <<>> ->
            	{:error, Http.reply(500, [], "Payload expected.", req)}
        	_any ->
            	case Json.decode(body) do
                	{:ok, decoded} when is_list(decoded) ->
                    	Session.received(decoded, session)
                    	:ok
                	{:error, _} ->
                    	{:error, Http.reply(500, [], "Broken JSON encoding.", req)}
            	end
    	end
  end

	@still_open {2010, "Another connection still open"}

	defp chunk_start(req, headers) do
    	chunk_start(req, headers, "application/javascript; charset=UTF-8")
  end

	defp chunk_start(req, headers, contentType) do
    	Http.chunk_start(200, [{"Content-Type", contentType}] ++ headers, req)
  end

  defp reply_loop(req, sessionId, responseLimit, fmt, service) do
    	req0 = Http.hook_tcp_close(req)
    	case Session.reply(sessionId) do
        	:wait -> receive do 
                              #In Cowboy we need to capture async
                              #messages from the tcp connection -
                              #ie: {active, once}.
                    	{:tcp_closed, _} ->
                                  req0
                              # In Cowboy we may in theory get real
                              # http requests, this is bad.
                              {:tcp, _s, data} ->
                                  :error_logger.error_msg(
                                    """
                                    Received unexpected data on a 
                                    long-polling http connection: ~p.
                                    Connection aborted.~n
                                    """,
                                    [data])
                                  req1 = Http.abruptly_kill(req)
                                  req1
                              :go ->
                                  req1 = Http.unhook_tcp_close(req0)
                                  reply_loop(req1, sessionId, responseLimit,
                                             fmt, service)
                      end
        	:session_in_use -> frame = Util.encode_frame({:close, @still_open})
                          	   chunk_end(req0, frame, fmt)
        	{:close, frame} -> frame = Util.encode_frame(frame)
                          		chunk_end(req0, frame, fmt)
        	{:ok, frame}    -> frame = Util.encode_frame(frame)
                          	   frame = :erlang.iolist_to_binary(frame)
                          	   req2 = chunk(req0, frame, fmt)
                          	reply_loop0(req2, sessionId,
                                      responseLimit - :erlang.size(frame),
                                      fmt, service)
    	end
  end

  defp reply_loop0(req, _sessionId, responseLimit, _fmt, _service) when responseLimit <= 0 do
    chunk_end(req)
  end

	defp reply_loop0(req, sessionId, responseLimit, fmt, service) do
    	reply_loop(req, sessionId, responseLimit, fmt, service)
  end

  defp chunk(req, body) do 
    {_, req} = Http.chunk(body, req)
    req
  end

	defp chunk(req, body, fmt), do: chunk(req, fmt.(body))

	defp chunk_end(req), do: Http.chunk_end(req)

	defp chunk_end(req, body, fmt) do 
		req = chunk(req, body, fmt)
    chunk_end(req)
  end

	defp fmt_xhr(body), do: [body, "\n"]

	defp fmt_eventsource(body) do
    	escaped = Util.url_escape(:erlang.binary_to_list(:erlang.iolist_to_binary(body)),
                                     "%\r\n\0") # $% must be first!
    	[<<"data: ">>, escaped, <<"\r\n\r\n">>]
  end

	defp fmt_htmlfile(body) do
    	double = Json.encode(:erlang.iolist_to_binary(body))
    	[<<"<script>\np(">>, double, <<");\n</script>\r\n">>]
  end

	defp fmt_jsonp(body, callback) do
    # Yes, JSONed twice, there isn't a a better way, we must pass
    # a string back, and the script, will be evaled() by the
    # browser.
    	[callback, "(", Json.encode(:erlang.iolist_to_binary(body)), ");\r\n"]
  end

	def websocket(req, headers, service) do
    	{_any, req, {isUpgradeOk?, isConnOk?}} = Handler.is_valid_ws(service, req)
    	case {isUpgradeOk?, isConnOk?} do
        	{false, _} ->
            	Http.reply(400, headers,
                              "Can \"Upgrade\" only to \"WebSocket\".", req)
        	{_, false} ->
            	Http.reply(400, headers,
                              "\"Connection\" must be \"Upgrade\"", req)
        	{true, true} ->
            	Http.reply(400, headers,
                              "This WebSocket request can't be handled.", req)
    	end
  end

	def rawwebsocket(req, headers, service) do
    websocket(req, headers, service)
  end

end

