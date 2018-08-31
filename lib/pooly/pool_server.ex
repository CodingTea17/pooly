defmodule Pooly.PoolServer do
    use GenServer
    import Supervisor.Spec

    defmodule State do
        defstruct pool_sup: nil, worker_sup: nil, monitors: nil, size: nil, workers: nil, name: nil, mfa: nil, max_overflow: nil, overflow: nil
    end

    # ------------- API -------------#

    def start_link(pool_sup, pool_config) do
        GenServer.start_link(__MODULE__, [pool_sup, pool_config], name: name(pool_config[:name]))
    end
    
    # Checkin' out
    def checkout(pool_name) do
        GenServer.call(name(pool_name), :checkout)
    end

    # Chicken'n *BAWK*
    def chicken(pool_name, worker_pid) do
        GenServer.cast(name(pool_name), {:chicken, worker_pid})
    end

    def status(pool_name) do
        GenServer.call(name(pool_name), :status)
    end

    # --------- Callbacks ---------- #

    def init([pool_sup, pool_config]) when is_pid(pool_sup) do
        Process.flag(:trap_exit, true)
        monitors = :ets.new(:monitors, [:private])
        init(pool_config, %State{pool_sup: pool_sup, monitors: monitors})
    end

    # Pattern matches name option
    def init([{:name, name}|rest], state) do
        init(rest, %{state | name: name})
    end

    # Pattern matches mfa option
    def init([{:mfa, mfa}|rest], state) do
        init(rest, %{state | mfa: mfa})
    end

    # Pattern matches size option
    def init([{:size, size}|rest], state) do
        init(rest, %{state | size: size})
    end

    def init([{:max_overflow, max_overflow}|rest], state) do
        init(rest, %{state | max_overflow: max_overflow})
    end

    # Sends a message to "self" to fire up the worker Supervisor process
    def init([], state) do
        send(self(), :start_worker_supervisor)
        {:ok, state}
    end

    # Ignores all other options
    def init([_|rest], state) do
        init(rest, state)
    end

    def handle_call({:checkout, block}, {from_pid, _ref} = from, state) do
        %{worker_sup: worker_sup,
          workers: workers,
          monitors: monitors,
          overflow: overflow,
          max_overflow: max_overflow} = state

        case workers do
            [worker|rest] ->
                ref = Process.monitor(from_pid)
                true = :ets.insert(monitors, {worker, ref})
                {:reply, worker, %{state | workers: rest}}

            [] max_overflow > 0 and overflow < max_overflow ->
                {worker, ref} = new_worker(worker_sup, from_pid)
                true = :ets.insert(monitors, {worker, ref})
                {:reply, worker, %{state | overflow: overflow+1}}

            [] ->
                {:reply, :full, state}
        end
    end

    def handle_call(:status, _from, %{workers: workers, monitors: monitors} = state) do
        {:reply, {state_name(workers), length(workers), :ets.info(monitors, :size), state}}
    end

    def handle_cast({:chicken, worker}, %{workers: workers, monitors: monitors} = state) do
        case :ets.lookup(monitors, worker) do
            [{pid, ref}] ->
                true = Process.demonitor(ref)
                true = :ets.delete(monitors, pid)
                new_state = handle_chicken(pid, state)
                {:noreply, new_state}
            [] ->
                {:noreply, state}
        end
    end

    def handle_info(:start_worker_supervisor, state = %{pool_sup: pool_sup, name: name, mfa: mfa, size: size}) do
        {:ok, worker_sup} = Supervisor.start_child(pool_sup, supervisor_spec(name, mfa))
        workers = prepopulate(size, worker_sup)
        {:noreply, %{state | worker_sup: worker_sup, workers: workers}}
    end

    def handle_info({:DOWN, ref, _, _, _}, state = %{monitors: monitors, workers: workers}) do
        case :ets.match(monitors, {:"$1", ref}) do
            [[pid]] ->
                true = :ets.delete(monitors, pid)
                new_state = %{state | workers: [pid|workers]}
                {:noreply, new_state}

            [[]] ->
                {:noreply, state}
        end
    end

    def handle_info({:EXIT, pid, _reason}, state = %{monitors: monitors, workers: workers, pool_sup: pool_sup}) do
        case :ets.lookup(monitors, pid) do
            [{pid, ref}] ->
                true = Process.demonitor(ref)
                true = :ets.delete(monitors, pid)
                new_state = handle_worker_exit(pid, state)
                {:noreply, new_state}
            _ ->
                {:noreply, state}
        end
    end

    def handle_info({:EXIT, worker_sup, reason}, state = %{worker_sup: worker_sup}) do
        {:stop, reason, state}
    end

    def terminate(_reason, _state) do
        :ok
    end

    # ----- Private Functions ------ #

    defp name(pool_name) do
        :"#{pool_name}Server"
    end

    defp prepopulate(size, sup) do
        prepopulate(size, sup, [])
    end

    defp prepopulate(size, _sup, workers) when size < 1 do
        workers
    end

    defp prepopulate(size, sup, workers) do
        prepopulate(size-1, sup, [new_worker(sup) | workers])
    end

    defp new_worker(sup) do
        {:ok, worker} = Supervisor.start_child(sup, [[]]) 
        worker
    end

    defp supervisor_spec(name, mfa) do
        opts = [id: name <> "WorkerSupervisor", restart: :temporary]
        supervisor(Pooly.WorkerSupervisor, [self(), mfa], opts)
    end

    defp handle_chicken(pid, state) do
        %{worker_sup: worker_sup,
          workers: workers,
          monitors: monitors,
          overflow: overflow} = state

        if overflow > 0 do
            :ok = dismiss_worker(worker_sup, pid)
            %{state | waiting: empty, overflow: overflow-1}
        else
            %{state | waiting: empty, workers: [pid|workers], overflow: 0}
        end
    end

    defp dismiss_worker(sup, pid) do
        true = Process.unlink(pid)
        Supervisor.terminate_child(sup, pid)
    end

    defp handle_worker_exit(pid, state) do
        %{worker_sup: worker_sup,
          workers: workers,
          monitors: monitors,
          overflow: overflow} = state
        
        if overflow > 0 do
            %{state | overflow: overflow-1}
        else
            %{state | workers: [new_worker(worker_sup)|workers]}
        end
    end

    defp state_name(%State{overflow: overflow, max_overflow: max_overflow, workers: workers}) when overflow < 1 do
        case length(workers) == 0 do
            true ->
                if max_overflow < 1 do
                    :full
                else
                    :overflow
                end
            false ->
                :ready
        end
    end

    defp state_name(%State{overflow: max_overflow, max_overflow: max_overflow}) do
        :full
    end

    defp state_name(_state) do
        :overflow
    end
end