defmodule Sockjs do
	use Application

	alias Sockjs.Session
	alias Sockjs.Session.Supervisor, as: SessionSup

	def start(_StartType, _StartArgs) do
		Session.init()
		SessionSup.start_link()
	end

end


