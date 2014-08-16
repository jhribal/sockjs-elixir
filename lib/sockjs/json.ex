defmodule Sockjs.Json do 
	use Jazz

	def encode(thing) do
		IO.puts "#ENCODING#"
		IO.inspect JSON.encode!(thing) 
	end

	def decode(encoded) do
		IO.puts "#DECODING#"
		IO.inspect {:ok, JSON.decode!(encoded)}
	end
end


