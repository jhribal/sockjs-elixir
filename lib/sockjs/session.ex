defmodule Sockjs.Session do 
	use GenServer

	alias Sockjs.Session
	alias Sockjs.Service

	defstruct id: nil,
			  outbound_queue: :queue.new(),
		  	  response_pid: nil,
			  disconnect_tref: nil,
		      disconnect_delay: 5000,
		      heartbeat_tref: nil,
		      heartbeat_delay: 25000,
		      ready_state: :connecting,
		      close_msg: nil,
		      callback: nil,
		      state: nil,
		      handle: nil


    @ets :sockjs_table

	def init() do
		_ = :ets.new(@ets, [:public, :named_table])
		:ok
	end

	def start_link(sessionId, service, info) do
		GenServer.start_link(__MODULE__, {sessionId, service, info}) 
	end

	def maybe_create(sessionId, service, info) do
		case :ets.lookup(@ets, sessionId) do
			[] -> {:ok, sspid} = Sockjs.Session.Supervisor.start_child(sessionId, service, info)
				  sspid
			[{_, sspid}] -> sspid
		end 
	end

	def received(message, sessionId) when is_pid(sessionId) do
		case GenServer.call(sessionId, {:received, message}, :infinity) do 
			:ok -> :ok
			:error -> throw(:no_session)
		end
	end

	def received(message, sessionId) do
		received(message, spid(sessionId)) 
	end

	def sendData(data, {__MODULE__, {sspid, _}}) do 
		GenServer.cast(sspid, {:send, data})
		:ok
	end

	def close(code, reason, {__MODULE__, {sspid, _}}) do
		GenServer.cast(sspid, {:close, code, reason})
		:ok 
	end

	def info({__MODULE__, {_sspid, info}}) do 
		info 
	end

	def reply(session) do
		reply(session, true) 
	end

	def reply(sessionPid, multiple) when is_pid(sessionPid) do
		GenServer.call(sessionPid, {:reply, self(), multiple}, :infinity) 
	end

	def reply(sessionId, multiple) do 
		reply(spid(sessionId), multiple)
	end

	##########################################################################

	defp cancel_timer_safe(timer, atom) do
		case :erlang.cancel_timer(timer) do 
			false ->
				receive do 
					^atom -> :ok
				after 
					0 -> :ok
				end
			_ -> :ok
		end
	end

	defp spid(sessionId) do 
		case :ets.lookup(@ets, sessionId) do
			[] -> throw(:no_session)
			[{_, sspid}] -> sspid 
		end
	end

	defp mark_waiting(pid, %Session{response_pid: pid, disconnect_tref: :undefined} = state) do
		state 
	end

	defp mark_waiting(pid, %Session{ response_pid: :undefined, 
								    disconnect_tref: disconnectTRef, 
								    heartbeat_delay: heartbeatDelay} = state) when disconnectTRef !== :undefined do
		Process.link(pid)
		cancel_timer_safe(disconnectTRef, :session_timeout)
		tRef = :erlang.send_after(heartbeatDelay, self(), :heartbeat_triggered)
		%Session{state | response_pid: pid, disconnect_tref: :undefined, heartbeat_tref: tRef} 
	end

	defp unmark_waiting(rpid, %Session{response_pid: rpid,
                                      heartbeat_tref: heartbeatTRef,
                                      disconnect_tref: :undefined,
                                      disconnect_delay: disconnectDelay} = state) do 
		Process.unlink(rpid)
		_ = case heartbeatTRef do 
				:undefined -> :ok
				:triggered -> :ok
				_Else -> cancel_timer_safe(heartbeatTRef, :heartbeat_triggered)
			end
		tRef = :erlang.send_after(disconnectDelay, self(), :session_timeout)
		%Session{state | response_pid: :undefined, disconnect_tref: tRef, heartbeat_tref: :undefined} 
    end 

    defp unmark_waiting(_pid, %Session{response_pid: :undefined,
                                      disconnect_tref: disconnectTRef,
                                      disconnect_delay: disconnectDelay} = state) when disconnectTRef !== :undefined do
    	cancel_timer_safe(disconnectTRef, :session_timeout)
    	tRef = :erlang.send_after(disconnectDelay, self(), :session_timeout)
    	%Session{state | disconnect_tref: tRef}
    end

    defp unmark_waiting(rpid, %Session{response_pid: pid, disconnect_tref: :undefined} = state)
    	when pid !== :undefined and pid !== rpid do
    	state
    end

    defp emit(what, %Session{callback: callback, 
    						state: userState,
    						handle: handle} = state) do 
    	r = case callback do 
    			_ when is_function(callback) ->
    					callback.(handle, what, userState)
    			_ when is_atom(callback) ->
    					case what do 
    						:init -> callback.sockjs_init(handle, userState)
    						{:recv, data} -> callback.sockjs_handle(handle, data, userState)
    						:closed -> callback.sockjs_terminate(handle, userState)
    					end
    		end
    	case r do 
    		{:ok, userState1} -> %Session{state | state: userState1}
    		{:ok } -> state
    	end

    end

    def init({sessionId, %Service{callback: callback,
    							  state: userState,
    							  disconnect_delay: disconnectDelay,
    							  heartbeat_delay: heartbeatDelay}, info}) do 
    	case sessionId do
    		:undefined -> :ok
    		_Else -> :ets.insert(@ets, {sessionId, self()}) 
    	end
    	Process.flag(:trap_exit, true)
    	tRef = :erlang.send_after(disconnectDelay, self(), :session_timeout)
    	{:ok, %Session{id: sessionId,
                  	   callback: callback,
                  	   state: userState,
                  	   response_pid: :undefined,
                  	   disconnect_tref: tRef,
                  	   disconnect_delay: disconnectDelay,
                  	   heartbeat_tref: :undefined,
                  	   heartbeat_delay: heartbeatDelay,
                  	   handle: {__MODULE__, {self(), info}}}}
    end


    def handle_call({:reply, pid, _multiple}, _from, %Session{response_pid: :undefined, ready_state: :connecting} = state) do 
    	state = emit(:init, state)
    	state = unmark_waiting(pid, state)
    	{:reply, {:ok, {:open, nil}}, %Session{state | ready_state: :open}}
    end

    def handle_call({:reply, pid, _multiple}, _from, %Session{ready_state: :closed, close_msg: closeMsg} = state) do
    	state = unmark_waiting(pid, state)
    	{:reply, {:close, {:close, closeMsg}}, state}
    end

    def handle_call({:reply, pid, _multiple}, _from, %Session{response_pid: rpid} = state)
    	when rpid !== pid and rpid !== :undefined do 
    	{:reply, :session_in_use, state}
    end

    def handle_call({:reply, pid, multiple}, _from, %Session{ready_state: :open,
                                             			     response_pid: rpid,
                                             				 heartbeat_tref: heartbeatTRef,
                                             				 outbound_queue: q} = state)
    	when rpid == :undefined or rpid == pid do 
    	{messages, q} = case multiple do 
    						true -> {:queue.to_list(q), :queue.new()}
    						false -> case :queue.out(q) do 
    									{{:value, msg}, q2} -> {[msg], q2}
    									{:empty, q2} -> {[], q2}
    								 end
    					 end
     	case {messages, heartbeatTRef} do
        {[], :triggered} -> state1 = unmark_waiting(pid, state)
                           {:reply, {:ok, {:heartbeat, nil}}, state1}
        {[], _TRef}     -> state1 = mark_waiting(pid, state)
                           {:reply, :wait, state1}
        _More           -> state1 = unmark_waiting(pid, state)
                           {:reply, {:ok, {:data, messages}},
                           %Session{state1 | outbound_queue: q}}
    	end
    end


    def handle_call({:received, messages}, _from, %Session{ready_state: :open} = state) do
    	state = :lists.foldl(fn (msg, state1) ->
                                 emit({:recv, :erlang.iolist_to_binary(msg)}, state1)
                         end, state, messages)
   		{:reply, :ok, state}
   	end

   	def handle_call({:received, _data}, _from, %Session{ready_state: _any} = state) do
    	{:reply, :error, state}
	end

	def handle_call(request, _from, state) do
    	{:stop, {:odd_request, request}, state}
    end

    def handle_cast({:send, data}, %Session{outbound_queue: q,
                                            response_pid: rpid} = state) do
    	case rpid do
        	:undefined -> :ok
        	_else     -> send(rpid, :go)
    	end
    	{:noreply, %Session{state | outbound_queue: :queue.in(data, q)}}
    end

    def handle_cast({:close, status, reason}, %Session{response_pid: rpid} = state) do
    	case rpid do
        	:undefined -> :ok
        	_else     -> send(rpid, :go)
    	end
    	{:noreply, %Session{state | ready_state: :closed, close_msg: {status, reason}}}
    end

    def handle_cast(cast, state) do 
    	{:stop, {:odd_cast, cast}, state}
    end

    def handle_info({:'EXIT', pid, _reason},
            %Session{response_pid: pid} = state) do
    	{:stop, :normal, %Session{state | response_pid: :undefined}}
    end

    def handle_info(:force_shutdown, state) do
    	{:stop, :normal, state}
	end

	def handle_info(:session_timeout, %Session{response_pid: :undefined} = state) do 
    	{:stop, :normal, state}
    end

    def handle_info(:heartbeat_triggered, %Session{response_pid: rpid} = state) when rpid !== :undefined do
    	send(rpid, :go)
    	{:noreply, %Session{state| heartbeat_tref: :triggered}}
    end

    def handle_info(info, state) do
    	{:stop, {:odd_info, info}, state}
    end

    def terminate(_, %Session{id: sessionId} = state) do
    	:ets.delete(@ets, sessionId)
    	_ = emit(:closed, state)
    	:ok
    end

    def code_change(_oldVsn, state, _extra) do
    	{:ok, state}
    end

end
