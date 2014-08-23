defmodule Sockjs.Json do 

	def encode(thing) do
		:mochijson2_fork.encode(thing) 
	end

	def decode(encoded) do
		{:ok, :mochijson2_fork.decode(encoded)}
	end
end


