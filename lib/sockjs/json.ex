defmodule Sockjs.Json do 

	def encode(thing) do
		:mochijson2_fork.encode(thing) 
	end

	def decode(encoded) do
		IO.inspect encoded
		IO.inspect JSON.decode(encoded)
		{:ok, :mochijson2_fork.decode(encoded)}
	end
end


