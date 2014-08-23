defmodule Sockjs.Cowboy.Handler do 

    @behaviour :cowboy_http_handler
    @behaviour :cowboy_websocket_handler

    alias Sockjs.Handler
    alias Sockjs.Service
    alias Sockjs.Session

    def init({_any, :http}, req, service) do
        case Handler.is_valid_ws(service, req) do
            {true, _req, _reason} ->
                {:upgrade, :protocol, :cowboy_websocket}
            {false, req, _reason} ->
                {:ok, req, service}
        end
    end

    def handle(req, service) do
        req = Handler.handle_req(service, req)
        {:ok, req, service}
    end

    def terminate(_reason, _req, _service) do
        :ok
    end

    def websocket_init(_transportName, req, %Service{logger: logger} = service) do
        req = logger.(service, req, :websocket)

        service = %Service{service | disconnect_delay: 5*60*1000}

        {info, req} = Handler.extract_info(req)
        sessionPid = Session.maybe_create(:undefined, service, info)
        {rawWebsocket, req } =
            case Handler.get_action(service, req) do
                {{:match, ws}, req} when ws == :websocket or
                                     ws == :rawwebsocket ->
                    {ws, req}
            end
        send(self(), :go)
        {:ok, req, {rawWebsocket, sessionPid}}
    end

    def websocket_handle({:text, data}, req, {rawWebsocket, sessionPid} = s) do
        case Sockjs.Ws.Handler.received(rawWebsocket, sessionPid, data) do
            :ok -> {:ok, req, s}
            :shutdown -> {:shutdown, req, s}
        end
    end

    def websocket_handle(_unknown, req, s) do
        {:shutdown, req, s}
    end


    def websocket_info(:go, req, {rawWebsocket, sessionPid} = s) do
        case Sockjs.Ws.Handler.reply(rawWebsocket, sessionPid) do
            :wait          -> {:ok, req, s}
            {:ok, data}    -> send(self(), :go)
                              {:reply, {:text, data}, req, s}
            {:close, ""} -> {:shutdown, req, s}
            {:close, data} -> send(self(), :shutdown)
                              {:reply, {:text, data}, req, s}
        end
    end

    def websocket_info(:shutdown, req, s) do
        {:shutdown, req, s}
    end

    def websocket_terminate(_reason, _req, {rawWebsocket, sessionPid}) do
        Sockjs.Ws.Handler.close(rawWebsocket, sessionPid)
        :ok
    end

end
