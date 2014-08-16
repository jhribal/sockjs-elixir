defmodule Sockjs.Service do

       defstruct prefix: nil,
              callback: nil, 
              state: nil,
              sockjs_url: nil,
              cookie_needed: nil,
              websocket: nil,
              disconnect_delay: nil,
              heartbeat_delay: nil,
              response_limit: nil,
              logger: nil 
end