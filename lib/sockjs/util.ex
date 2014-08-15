defmodule Sockjs.Util do 

	def rand32() do
    	case Process.get(:random_seeded) do
        	:undefined ->
            	{megaSecs, secs, microSecs} = :erlang.now()
            	_ = :random.seed(megaSecs, secs, microSecs)
            	Process.put(:random_seeded, true)
        	_else ->
            	:ok
    	end
    	:random.uniform(:erlang.trunc(:math.pow(2,32)))-1
    end

	def encode_frame({:open, nil}) do
    	<<"o">>
    end

	def encode_frame({:close, {code, reason}}) do
    	[<<"c">>,
     		Json.encode([code, :erlang.list_to_binary(reason)])]
    end

	def encode_frame({:data, l}) do
    	[<<"a">>, 
     		#Json.encode([:erlang.iolist_to_binary(d) || d <- l])]
     		Json.encode(Enum.map(l, fn d -> :erlang.iolist_to_binary(d) end))]
    end

	def encode_frame({:heartbeat, nil}) do
    	<<"h">>
    end

	def url_escape(str, chars) do
    	#[case :lists.member(char, chars) do
        # 	true  -> hex(char)
        # 	false -> char
     	#	end || char <- str]
     	Enum.each(str, fn char -> 
     						case :list.member(char, chars) do
     							true -> hex(char)
     							false -> char
     						end
     					end)
     end

    defp hex(c) do
    	<<high0::4, low0::4>> = <<c>>
    	high = :erlang.integer_to_list(high0)
    	low = :erlang.integer_to_list(low0)
    	"%" ++ high ++ low
    end

end



