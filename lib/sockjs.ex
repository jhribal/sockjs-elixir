defmodule Sockjs do
	use Application

	alias Sockjs.Session
	alias Sockjs.Session.Supervisor, as: SessionSup

	def start(_StartType, _StartArgs) do
		Session.init()
		SessionSup.start_link()
	end

	def send(data, {:sockjs_session, _} = conn) do
    	Session.sendData(data, conn)
   	end

	def close(conn) do
    	close(1000, "Normal closure", conn)
    end

	def close(code, reason, {:sockjs_session, _} = conn) do
    	Session.close(code, reason, conn)
    end

	def info({:sockjs_session, _} = conn) do
    	Session.info(conn)
    end

end


