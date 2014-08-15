defmodule Sockjs.Session.Supervisor do 
	use Supervisor

	def start_link() do
		Supervisor.start_link(__MODULE__, [], name: __MODULE__) 
	end 

	def init([]) do
		children = [worker(Sockjs.Session, [], restart: :transient, shutdown: 5000, id: :undefined)]
		#children = [{:undefined, {Sockjs.Session, :start_link, []}, :transient, 5000, :worker, [Sockjs.Session]}]
		supervise(children, strategy: :simple_one_for_one, max_restarts: 10, max_seconds: 10) 
	end

	def start_child(sessionId, service, info) do
   		Supervisor.start_child(__MODULE__, [sessionId, service, info])
   	end
end

