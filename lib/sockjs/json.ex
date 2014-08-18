defmodule Sockjs.Json do 

	def encode(thing) do
		#IO.puts "#ENCODING#"
		#{:ok, enc} = JSON.encode(thing)
		#enc
		:mochijson2_fork.encode(thing) 
	end

	def decode(encoded) do
		#IO.puts "#DECODING#"
		{:ok, JSON.decode!(encoded)}
	end
end


