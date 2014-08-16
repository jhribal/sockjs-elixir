defmodule Sockjs.Json do 
	use Jazz

	def encode(thing) do
		IO.puts "calling encode.."
		r = JSON.encode!(thing)
		IO.inspect r 
	end

	def decode(encoded) do
		{:ok, JSON.decode!(encoded)}
	end
end


