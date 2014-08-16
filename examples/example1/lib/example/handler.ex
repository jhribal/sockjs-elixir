defmodule Example.Handler do

	alias Sockjs.Session

	# this should be changed
	def sockjs_init({_, {spid,_}}, state) do
		IO.puts "!!!!!!! HANDLER INIT !!!!!!!!!!"
		Session.sendData(spid, [%{message: "Ahoj"}])
		{:ok, state} 
	end

	def sockjs_handle({_, {spid,_}}, data, state) do
		{:ok, state} 
	end

	def sockjs_terminate({_, {spid,_}}, state) do
		{:ok, state} 
	end

end