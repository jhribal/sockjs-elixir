defmodule Sockjs.Http do

	def path(req) do     
        :cowboy_req.path(req)
	end

	def method(req) do 
		{method, req} = :cowboy_req.method(req)
		{method_atom(method), req}
	end

	defp method_atom("GET"), do: :'GET'
	defp method_atom("PUT"), do: :'PUT'
	defp method_atom("POST"), do: :'POST'
	defp method_atom("DELETE"), do: :'DELETE'
	defp method_atom("OPTIONS"), do: :'OPTIONS'
	defp method_atom("PATCH"), do: :'PATCH'
	defp method_atom("HEAD"), do: :'HEAD'
	defp method_atom(:'GET'), do: :'GET'
	defp method_atom(:'PUT'), do: :'PUT'
	defp method_atom(:'POST'), do: :'POST'
	defp method_atom(:'DELETE'), do: :'DELETE'
	defp method_atom(:'OPTIONS'), do: :'OPTIONS'
	defp method_atom(:'PATCH'), do: :'PATCH'
	defp method_atom(:'HEAD'), do: :'HEAD'

	def body(req) do 
		{:ok, body, req} = :cowboy_req.body(req)
        {body, req}
    end

	def body_qs(req) do
    	{h, req} = header("content-type", req)
    	case h do
            h when h == "text/plain" or h == "" ->
            	body(req)
        	_ ->
            	# By default assume application/x-www-form-urlencoded
            	body_qs2(req)
    	end
    end


	defp body_qs2(req) do
    	{:ok, bodyQS, req} = :cowboy_req.body_qs(req)
    	case Keyword.get(bodyQS, "d", :undefined) do
        	:undefined ->
            	{"", req}
        	v ->
            	{v, req}
        end
    end

	def header(h, req) do
        :cowboy_req.header(h, req)
    end

	def jsessionid(req) do
        :cowboy_req.cookie("jsessionid", req)
    end

    def callback(req) do
        :cowboy_req.qs_val("c", req)
    end

	def peername(req) do
        :cowboy_req.peer(req)
    end

	def sockname(req) do
    	:cowboy_req.peer(req)
    end

	def reply(code, headers, body, req) do
    	#body = :erlang.iolist_to_binary(body)
    	#{:ok, req} = :cowboy_req.reply(code, enbinary(headers), body, req)
        {:ok, req} = :cowboy_req.reply(code, headers, body, req)
    	req
    end

	def chunk_start(code, headers, req) do
    	#{:ok, req} = :cowboy_req.chunked_reply(code, enbinary(headers), req)
        {:ok, req} = :cowboy_req.chunked_reply(code, headers, req)
    	req
    end

    def chunk(chunk, req) do
    	case :cowboy_req.chunk(chunk, req) do
        	:ok -> 
                {:ok, req}
        	{:error, _e} -> 
                {:error, req}
                      # This shouldn't happen too often, usually we
                      # should catch tco socket closure before.
    	end
    end

    # this should really does nothing?
	def chunk_end(req), do: req

    # why is this needed?
	# defp enbinary(l), do: Enum.map(l, fn {k, v} -> {:erlang.list_to_binary(k), :erlang.list_to_binary(v)} end)

	#enbinary(L) -> [{list_to_binary(K), list_to_binary(V)} || {K, V} <- L].

	def hook_tcp_close(req) do
    	[t, s] = :cowboy_req.get([:transport, :socket], req)
    	t.setopts(s,[{:active,:once}])
    	req
	end

	def unhook_tcp_close(req) do
    	[t, s] = :cowboy_req.get([:transport, :socket], req)
    	t.setopts(s,[{:active,false}])
    	req
    end

	def abruptly_kill(req) do
    	[t, s] = :cowboy_req.get([:transport, :socket], req)
    	:ok = t.close(s)
    	req
    end

end
