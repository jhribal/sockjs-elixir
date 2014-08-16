defmodule Example.Handler do

	def sockjs_init(handle, state) do
		IO.puts "!!!!!!! HANDLER INIT !!!!!!!!!!"
		{:ok, state} 
	end

	def sockjs_handle(handle, data, state) do
		{:ok, state} 
	end

	def sockjs_terminate(handle, state) do
		{:ok, state} 
	end

end