defmodule Sockjs.Json do 
	use Jazz

	def encode(thing) do
		JSON.encode!(thing) 
	end

	def decode(encoded) do
		{:ok, JSON.decode!(encoded)}
	end
end


