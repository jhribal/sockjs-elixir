defmodule Sockjs.Filters do 

  alias Sockjs.Http
  
	@year 365 * 24 * 60 * 60

	def cache_for(req, headers) do
      expires = :calendar.gregorian_seconds_to_datetime(
                	:calendar.datetime_to_gregorian_seconds(
                  :calendar.now_to_datetime(:erlang.now())) + @year)
    	h = [{"Cache-Control", 'public, max-age=' ++ :erlang.integer_to_list(@year)},
         {"Expires",       :httpd_util.rfc1123_date(expires)}]
    	{h ++ headers, req}
    end

	def h_sid(req, headers) do
    # Some load balancers do sticky sessions, but only if there is
    # a JSESSIONID cookie. If this cookie isn't yet set, we shall
    # set it to a dumb value. It doesn't really matter what, as
    # session information is usually added by the load balancer.
    	{c, req} = Http.jsessionid(req)
    	h = case c do
        	:undefined -> [{"Set-Cookie", "JSESSIONID=dummy; path=/"}]
        	jsid      -> [{"Set-Cookie", "JSESSIONID=" ++ jsid ++ "; path=/"}]
    	end
    	{h ++ headers, req}
    end


	def h_no_cache(req, headers) do
    	h = [{"Cache-Control", "no-store, no-cache, must-revalidate, max-age=0"}]
    	{h ++ headers, req}
    end

	def xhr_cors(req, headers) do
    	{originH, req} = Http.header(:'origin', req)
      IO.puts "aaaa"
     	origin = case originH do
                  "null" -> "*"
                  :undefined -> "*"
                  O         -> O
              	 end
    	{headersH, req} = Http.header(
                             :'access-control-request-headers', req)
    	allowHeaders = case headersH do
                       :undefined -> []
                       v         -> [{"Access-Control-Allow-Headers", v}]
                   	   end
    	h = [{"Access-Control-Allow-Origin",      origin},
         {"Access-Control-Allow-Credentials", "true"}]
      IO.puts "xhr_cors endinf.."
    	{h ++ allowHeaders ++ headers, req}
    end

	def xhr_options_post(req, headers) do
    	xhr_options(req, headers, ["OPTIONS", "POST"])
    end

	def xhr_options_get(req, headers) do
    	xhr_options(req, headers, ["OPTIONS", "GET"])
    end

	defp xhr_options(req, headers, methods) do
    	h = [{"Access-Control-Allow-Methods", :string.join(methods, ", ")},
         {"Access-Control-Max-Age", :erlang.integer_to_list(@year)}]
    	{h ++ headers, req}
    end

end

