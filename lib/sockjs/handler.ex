defmodule Sockjs.Handler do 

	alias Sockjs.Service
  alias Sockjs.Http
  alias Sockjs.Filters
  alias Sockjs.Action
  alias Sockjs.Session 
  
	@sockjs_url "https://d1fxtkz8shb9d2.cloudfront.net/sockjs-0.3.min.js"

  defmacro __using__([]) do

    quote do
      import unquote(__MODULE__), only: :macros

      init do 
      end
      handle do 
      end 
      terminate do 
      end

      defoverridable [sockjs_init: 3, sockjs_handle: 4, sockjs_terminate: 3]

    end

  end

  defmacro reply(data) do
    quote do
      Sockjs.Session.sendData(var!(spid), unquote(data)) 
    end 
  end

  defmacro close(code, reason) do
    quote do
      Sockjs.Session.close(var!(spid), unquote(code), unquote(reason)) 
    end 
  end

  defmacro init(do: body) do

    quote do
      def sockjs_init(var!(spid), var!(info), var!(state)) do
        unquote(body)
        {:ok, var!(state)} 
      end 
    end

  end

  defmacro handle(do: body) do
    quote do 
      def sockjs_handle(var!(spid), var!(info), var!(data), var!(state)) do
        unquote(body)
        {:ok, var!(state)}
      end
    end 
  end

  defmacro terminate(do: body) do
    quote do 
      def sockjs_terminate(var!(spid), var!(info), var!(state)) do
        unquote(body)
        {:ok, var!(state)} 
      end
    end 
  end

	def init_state(prefix, callback, state, options) do
	    %Service{prefix: prefix,
	             callback: callback,
	             state: state,
	             sockjs_url: Keyword.get(options, :sockjs_url, @sockjs_url),
	             websocket: Keyword.get(options, :websocket, true),
	             cookie_needed: Keyword.get(options, :cookie_needed, false),
	             disconnect_delay: Keyword.get(options, :disconnect_delay, 5000),
	             heartbeat_delay: Keyword.get(options, :heartbeat_delay, 25000),
	             response_limit: Keyword.get(options, :response_limit, 128*1024),
	             logger: Keyword.get(options, :logger, &default_logger/3)}
	end

	def is_valid_ws(service, req) do
    	case get_action(service, req) do
        	{{:match, ws}, req} when ws != :websocket or ws != :rawwebsocket ->
            	valid_ws_request(service, req)
        	{_else, req} ->
            	{false, req, {}}
    	end
  end

	defp valid_ws_request(_service, req) do
    	{isUpgradeOk?, req} = valid_ws_upgrade(req)
    	{isConnOk?, req} = valid_ws_connection(req)
    	{isUpgradeOk? and isConnOk?, req, {isUpgradeOk?, isConnOk?}}
  end

  defp valid_ws_upgrade(req) do
    	case Http.header("upgrade", req) do
        	{:undefined, req} ->
            	{false, req}
        	{upgrade_val, req} ->
            	case String.downcase(upgrade_val) do
                	"websocket" ->
                    	{true, req}
                	_ ->
                    	{false, req}
            	end
      end
  end

	defp valid_ws_connection(req) do
   		case Http.header("connection", req) do
        	{:undefined, req} ->
            	{false, req}
        	{conn_val, req} ->
        		conn_val_parts = Enum.map(String.split(String.downcase(conn_val), ","), fn (t) -> String.strip(t) end)
            {Enum.member?(conn_val_parts, "upgrade"), req}
    	end
  end

	def get_action(service, req) do
    	{dispatch, req} = dispatch_req(service, req)
    	case dispatch do
        	{:match, {_, action, _, _, _}} ->
            	{{:match, action}, req};
        	_ ->
            	{:nomatch, req}
    	end
    end

    defp strip_prefix(longPath, prefix) do
    	{a, b} = String.split_at(longPath, String.length(prefix))
      # is this function really needed? Cowboy will not handle request with sockjs handler if
      # the prefix didn't matched
    	case prefix do
        	^a -> {:ok, b}
        	#_any -> {:error, :io_lib.format("Wrong prefix: ~p is not ~p", [a, prefix])}
          _ -> {:error, "Wrong prefix: #{a} is not #{prefix}"}
    	end
    end


    def dispatch_req(%Service{prefix: prefix}, req) do
    	{method, req} = Http.method(req)
    	{longPath, req} = Http.path(req)
    	{:ok, pathRemainder} = strip_prefix(longPath, prefix)
    	{dispatch(method, pathRemainder), req}
    end

	defp dispatch(method, path) do
    	:lists.foldl(
      		fn ({match, methodFilters}, :nomatch) ->
            	case match.(path) do
                	:nomatch ->
                    	:nomatch
                  	[server, session] ->
                    	case :lists.keyfind(method, 1, methodFilters) do
                        	false ->
                              	#methods = [ k || {k, _, _, _} <- methodFilters]
                              	methods = Enum.map(methodFilters, fn {k,_,_,_} -> k end)
                              	{:bad_method, methods}
                          	{_method, type, a, filters} ->
                            	{:match, {type, a, server, session, filters}}
                      	end
               	end
          		(_, result) ->
              		result
      		end, :nomatch, filters())
    end

    defp filters() do
    	optsFilters = [:h_sid, :xhr_cors, :cache_for, :xhr_options_post]
    	# websocket does not actually go via handle_req/3 but we need
    	# something in dispatch/2
    	[{t('/websocket'),              [{:'GET',     :none, :websocket,      []}]},
     	{t('/xhr_send'),                [{:'POST',    :recv, :xhr_send,       [:h_sid, :h_no_cache, :xhr_cors]},
                                      	{:'OPTIONS', :none, :options,        optsFilters}]},
     	{t('/xhr'),                     [{:'POST',    :send, :xhr_polling,    [:h_sid, :h_no_cache, :xhr_cors]},
                                      	{:'OPTIONS', :none, :options,        optsFilters}]},
     	{t('/xhr_streaming'),           [{:'POST',    :send, :xhr_streaming,  [:h_sid, :h_no_cache, :xhr_cors]},
                                      	{:'OPTIONS', :none, :options,        optsFilters}]},
     	{t('/jsonp_send'),              [{:'POST',    :recv, :jsonp_send,     [:h_sid, :h_no_cache]}]},
     	{t('/jsonp'),                   [{:'GET',     :send, :jsonp,          [:h_sid, :h_no_cache]}]},
     	{t('/eventsource'),             [{:'GET',     :send, :eventsource,    [:h_sid, :h_no_cache]}]},
     	{t('/htmlfile'),                [{:'GET',     :send, :htmlfile,       [:h_sid, :h_no_cache]}]},
     	{p('/websocket'),               [{:'GET',     :none, :rawwebsocket,   []}]},
     	{p(''),                         [{:'GET',     :none, :welcome_screen, []}]},
     	{p('/iframe[0-9-.a-z_]*.html'), [{:'GET',     :none, :iframe,         [:cache_for]}]},
     	{p('/info'),                    [{:'GET',     :none, :info_test,      [:h_no_cache, :xhr_cors]},
                                      	{:'OPTIONS', :none, :options,        [:h_sid, :xhr_cors, :cache_for, :xhr_options_get]}]}
    	]
    end


	defp p(s), do: fn (path) -> re(path, '^' ++ s ++ '[/]?\$') end
	defp t(s), do: fn (path) -> re(path, '^/([^/.]+)/([^/.]+)' ++ s ++ '[/]?\$') end

	defp re(path, s) do
    	case :re.run(path, s, [{:capture, :all_but_first, :list}]) do
        	:nomatch                    -> :nomatch
        	{:match, []}                -> [:dummy, :dummy]
        	{:match, [server, session]} -> [server, session]
    	end
    end


    def handle_req(%Service{logger: logger} = service, req) do
      req = logger.(service, req, :http)
      {dispatch, req} = dispatch_req(service, req)
      handle(dispatch, service, req)
    end

    defp handle(:nomatch, _service, req) do
    	Http.reply(404, [], "", req)
    end

    defp handle({:bad_method, methods}, _service, req) do
    	#methodsStr = :string.join([:erlang.atom_to_list(m) || m <- methods], ", ")
    	methodsStr = :string.join(Enum.map(methods, fn m -> :erlang.atom_to_list(m) end), ", ")
    	h = [{"Allow", methodsStr}]
    	Http.reply(405, h, "", req)
    end

    defp handle({:match, {type, action, _server, session, filters}}, service, req) do
      {headers, req} = List.foldl(filters, {[], req}, fn (filter, {headers, req}) ->
                                                          apply(Filters, filter, [req, headers])
                                                      end)
    	case type do
        	:send ->
            	{info, req} = extract_info(req)
            	_spid = Session.maybe_create(session, service, info)
              apply(Action, action, [req, headers, service, session])
            	#Action.action(req, headers, service, session)
        	:recv ->
            	try do
                  apply(Action, action, [req, headers, service, session])
                	#Action.action(req, headers, service, session)
            	catch throw: :no_session ->
                	{h, req} = Filters.h_sid(req, [])
                  Http.reply(404, h, "", req)
            	end
        	:none ->
              apply(Action, action, [req, headers, service])
            	#Action.action(req, headers, service)
    	end
    end


  @doc false
	defp default_logger(_service, req, _type) do
    	{longPath, req} = Http.path(req)
    	{method, req}   = Http.method(req)
    	:io.format("~s ~s~n", [method, longPath])
    	req
    end

  @doc false
	def extract_info(req) do
    	{peer, req}    = Http.peername(req)
    	{sock, req}    = Http.sockname(req)
    	{path, req}    = Http.path(req)
      {headers, req} = List.foldl([:'referer', :'x-client-ip', :'x-forwarded-for', :'x-cluster-client-ip', :'via', :'x-real-ip'],
                                  {[], req}, fn (h, {acc, req}) -> 
                                                case Http.header(h, req) do 
                                                  {:undefined, r} -> {acc, r}
                                                  {v, r} -> {[{h, v} | acc], r}
                                                end
                                              end)
    	{[{:peername, peer}, {:sockname, sock}, {:path, path}, {:headers, headers}], req}
    end

end

