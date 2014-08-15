defmodule Sockjs.Http do

	def path({:cowboy, req}) do     
		{path, req} = :cowboy_req.path(req)
		{:erlang.binary_to_list(path), {:cowboy, req}}
	end

	def method({:cowboy, req}) do 
		{method, req} = :cowboy_req.method(req)
		{method_atom(method), {:cowboy, req}}
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

	def body({:cowboy, req}) do 
		{:ok, body, req} = :cowboy_req.body(req)
        {body, {:cowboy, req}}
    end

	def body_qs(req) do
    	{h, req} =  header(:'content-type', req)
    	case h do
        	h when h === "text/plain" or h === "" ->
            	body(req)
        	_ ->
            	# By default assume application/x-www-form-urlencoded
            	body_qs2(req)
    	end
    end


	defp body_qs2({:cowboy, req}) do
    	{:ok, bodyQS, req} = :cowboy_req.body_qs(req)
    	case :proplists.get_value(<<"d">>, bodyQS) do
        	:undefined ->
            	{<<>>, {:cowboy, req}}
        	v ->
            	{v, {:cowboy, req}}
        end
    end

	def header(k, {:cowboy, req}) do
    	{h, req} = :cowboy_req.header(k, req)
    	{v, req} = case h do
                   		:undefined ->
                        	:cowboy_req.header(:erlang.atom_to_binary(k, :utf8), req)
                    	_ -> {h, req}
                   end
    	case v do
        	:undefined -> {:undefined, {:cowboy, req}}
        	_ -> {:erlang.binary_to_list(v), {:cowboy, req}}
        end
    end

	def jsessionid({:cowboy, req}) do
    	{c, req} = :cowboy_req.cookie(<<"jsessionid">>, req)
    	case c do
        	_ when is_binary(c) ->
            	{:erlang.binary_to_list(c), {:cowboy, req}}
        	:undefined ->
            	{:undefined, {:cowboy, req}}
    	end
    end

    def callback({:cowboy, req}) do
    	{cb, req} = :cowboy_req.qs_val(<<"c">>, req)
    	case cb do
        	:undefined -> {:undefined, {:cowboy, req}}
        	_ -> {:erlang.binary_to_list(cb), {:cowboy, req}}
        end
    end

	def peername({:cowboy, req}) do
    	{p, req} = :cowboy_req.peer(req)
    	{p, {:cowboy, req}}
    end

	def sockname({:cowboy, req} = r) do
    	{addr, _req} = :cowboy_req.peer(req)
    	{addr, r}
    end

	def reply(code, headers, body, {:cowboy, req}) do
    	body = :erlang.iolist_to_binary(body)
    	{:ok, req} = :cowboy_req.reply(code, enbinary(headers), body, req)
    	{:cowboy, req}
    end

	def chunk_start(code, headers, {:cowboy, req}) do
    	{:ok, req} = :cowboy_req.chunked_reply(code, enbinary(headers), req)
    	{:cowboy, req}
    end

    def chunk(chunk, {:cowboy, req} = r) do
    	case :cowboy_req.chunk(chunk, req) do
        	:ok -> {:ok, r}
        	{:error, _e} -> {:error, r}
                      # This shouldn't happen too often, usually we
                      # should catch tco socket closure before.
    	end
    end

	def chunk_end({:cowboy, _req} = r), do: r


	defp enbinary(l), do: Enum.map(l, fn {k, v} -> {:erlang.list_to_binary(k), :erlang.list_to_binary(v)} end)

	#enbinary(L) -> [{list_to_binary(K), list_to_binary(V)} || {K, V} <- L].

	def hook_tcp_close({:cowboy, req} = r) do
    	[t, s] = :cowboy_req.get([:transport, :socket], req)
    	t.setopts(s,[{:active,:once}])
    	r
	end

	def unhook_tcp_close({:cowboy, req} = r) do
    	[t, s] = :cowboy_req.get([:transport, :socket], req)
    	t.setopts(s,[{:active,false}])
    	r 
    end

	def abruptly_kill({:cowboy, req} = r) do
    	[t, s] = :cowboy_req.get([:transport, :socket], req)
    	:ok = t.close(s)
    	r
    end

end
