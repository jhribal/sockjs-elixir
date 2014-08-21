defmodule Example do
	use Application

	def start(_type, _args) do

		:application.start(:crypto)
		:application.start(:ranch)
		:application.start(:cowlib)
		:application.start(:cowboy)

		IO.inspect :mochijson2_fork.decode(["{\"type\":\"message\",\"data\":{\"msg\":\"Hello world!\"}}"])

		state = Sockjs.Handler.init_state("/rt", Example.Handler , :state, [])

		dispatch = :cowboy_router.compile([
    		{:_, [
    			{"/rt/[...]", Sockjs.Cowboy.Handler, state},
    			{"/", :cowboy_static, {:priv_file, :example1, "index.html"}},
    			{"/[...]", :cowboy_static, {:priv_dir, :example1, ""}}]}
    	])

    	:cowboy.start_http(:my_http_listener, 100, [port: 4040],
   			[env: [dispatch: dispatch]])

	end

end

