defmodule Sockjs.Ws.Handler do 

	alias Sockjs.Json
	alias Sockjs.Util
	alias Sockjs.Session 
    
	# Ignore empty
	def received(_rawWebsocket, _sessionPid, <<>>) do
    	:ok
    end

	def received(:websocket, sessionPid, data) do
    	case Json.decode(data) do
        	{:ok, msg} when is_binary(msg) ->
            	session_received([msg], sessionPid)
        	{:ok, messages} when is_list(messages) ->
            	session_received(messages, sessionPid)
        	_else ->
            	:shutdown
        end
    end

    def received(:rawwebsocket, sessionPid, data) do
   		session_received([data], sessionPid)
   	end

   	defp session_received(messages, sessionPid) do
    	try do
        	:ok = Session.received(messages, sessionPid)
    	catch
        	:no_session -> :shutdown
    	end
    end

	def reply(:websocket, sessionPid) do
    	case Session.reply(sessionPid) do
        	{w, frame} when w !== :ok or w !== :close ->
            	frame = Util.encode_frame(frame)
            	{w, :erlang.iolist_to_binary(frame)}
        	:wait ->
            	:wait
        end
    end

    def reply(:rawwebsocket, sessionPid) do
    	case Session.reply(sessionPid, false) do
        	{w, frame} when w !== :ok or w !== :close ->
            	case frame do
                	{:open, nil}               -> reply(:rawwebsocket, sessionPid)
                	{:close, {_code, _reason}} -> {:close, <<>>}
                	{:data, [msg]}             -> {:ok, :erlang.iolist_to_binary(msg)}
                	{:heartbeat, nil}          -> reply(:rawwebsocket, sessionPid)
            	end
        	:wait ->
            	:wait
        end
    end

	def close(_rawWebsocket, sessionPid) do
    	send(sessionPid, :force_shutdown)
    	:ok
    end

end

