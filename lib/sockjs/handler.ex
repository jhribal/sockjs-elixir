defmodule Sockjs.Handler do 

	alias Sockjs.Service
  alias Sockjs.Http
  alias Sockjs.Filters
  alias Sockjs.Action

	@sockjs_url "https://d1fxtkz8shb9d2.cloudfront.net/sockjs-0.3.min.js"

	def init_state(prefix, callback, state, options) do
	    %Service{prefix: :erlang.binary_to_list(prefix),
	             callback: callback,
	             state: state,
	             sockjs_url: :proplists.get_value(:sockjs_url, options, @sockjs_url),
	             websocket: :proplists.get_value(:websocket, options, true),
	             cookie_needed: :proplists.get_value(:cookie_needed, options, false),
	             disconnect_delay: :proplists.get_value(:disconnect_delay, options, 5000),
	             heartbeat_delay: :proplists.get_value(:heartbeat_delay, options, 25000),
	             response_limit: :proplists.get_value(:response_limit, options, 128*1024),
	             logger: :proplists.get_value(:logger, options, &default_logger/3)
	            }
	end


	def is_valid_ws(service, req) do
      IO.puts "validating ws request.."
    	case get_action(service, req) do
        	{{:match, ws}, req1} when ws !== :websocket or
                                 ws !== :rawwebsocket ->
              IO.puts "calling valid_ws_request..."
            	valid_ws_request(service, req1)
        	{_else, req1} ->
              IO.puts "invalid ws request"
            	{false, req1, {}}
    	end
    end

	defp valid_ws_request(_service, req) do
    	{r1, req} = valid_ws_upgrade(req)
    	{r2, req} = valid_ws_connection(req)
    	{r1 and r2, req, {r1, r2}}
    end

    defp valid_ws_upgrade(req) do
    	case Http.header("upgrade", req) do
        	{:undefined, req2} ->
            	{false, req2}
        	{v, req2} ->
            	case :string.to_lower(v) do
                	'websocket' ->
                      IO.puts "zmrdiiiiii"
                    	{true, req2}
                	_else ->
                    	{false, req2}
            	end
    	end
    end

	defp valid_ws_connection(req) do
   		case Http.header(:'connection', req) do
        	{:undefined, req2} ->
            	{false, req2}
        	{v, req2} ->
            IO.puts v
        		vs = Enum.map(:string.tokens(:string.to_lower(v), ','), fn t -> :string.strip(t) end)
            	#vs = [:string:strip(t) || t <- :string.tokens(:string.to_lower(v), ",")]
            	{:lists.member('upgrade', vs), req2}
    	end
    end

	def get_action(service, req) do
    	{dispatch, req} = dispatch_req(service, req)
      IO.puts "dispatch request performed..."
    	case dispatch do
        	{:match, {_, action, _, _, _}} ->
            	{{:match, action}, req};
        	_else ->
            	{:nomatch, req}
    	end
    end

    defp strip_prefix(longPath, prefix) do
    	{a, b} = :lists.split(length(prefix), longPath)
    	case prefix do
        	^a -> {:ok, b}
        	_any -> {:error, :io_lib.format("Wrong prefix: ~p is not ~p", [a, prefix])}
    	end
    end


    def dispatch_req(%Service{prefix: prefix}, req) do
      IO.puts "trying perform dispatch_req..."
    	{method, req} = Http.method(req)
      IO.puts "got method..."
    	{longPath, req} = Http.path(req)
      IO.puts "got path"
    	{:ok, pathRemainder} = strip_prefix(longPath, prefix)
      IO.puts "prefix stripped..."
      IO.puts "going to call dispatch..."
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
      IO.puts "calling handle..."
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
      IO.puts "inside handle..."
      IO.inspect filters
    	{headers, req} = :lists.foldl(
                        	fn (filter, {headers0, req1}) ->
                             apply(Filters, filter, [req1, headers0])
                            	#Filters.filter(req1, headers0)
                        	end, {[], req}, filters)
      IO.puts "handle first part completed"
      IO.inspect type
    	case type do
        	:send ->
              IO.puts "send type..."
            	{info, req} = extract_info(req)
            	_spid = Session.maybe_create(session, service, info)
              apply(Action, action, [req, headers, service, session])
            	#Action.action(req, headers, service, session)
        	:recv ->
              IO.puts "recv type.."
            	try do
                  apply(Action, action, [req, headers, service, session])
                	#Action.action(req, headers, service, session)
            	catch throw: :no_session ->
                	{h, req} = Filters.h_sid(req, [])
                  Http.reply(404, h, "", req)
            	end
        	:none ->
              IO.inspect action
              apply(Action, action, [req, headers, service])
            	#Action.action(req, headers, service)
    	end
    end


	defp default_logger(_service, req, _type) do
    	{longPath, req} = Http.path(req)
    	{method, req}   = Http.method(req)
    	:io.format("~s ~s~n", [method, longPath])
    	req
    end

	def extract_info(req) do
    	{peer, req}    =  Http.peername(req)
    	{sock, req}    = Http.sockname(req)
    	{path, req}    = Http.path(req)
    	{headers, req} = :lists.foldl(fn (h, {acc, r0}) ->
                                      	case Http.header(h, r0) do
                                              {:undefined, r1} -> {acc, r1}
                                              {v, r1}         -> {[{h, v} | acc], r1}
                                        end
                                  	  end, {[], req},
                                  	[:'referer', :'x-client-ip', :'x-forwarded-for',
                                   	 :'x-cluster-client-ip', :'via', :'x-real-ip'])
    	{[{:peername, peer}, {:sockname, sock}, {:path, path}, {:headers, headers}], req}
    end

end

