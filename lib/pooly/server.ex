defmodule Pooly.Server do
    use GenServer
    import Supervisor.Spec

    # ------------- API -------------#
    
    def start_link(sup, pool_config) do
        GenServer.start_link(__MODULE__, [sup, pool_config], name: __MODULE__)
    end

    defmodule State do
        defstruct sup: nil, size: nil, mfa: nil
    end

    # Checkin' out
    def checkout do
        GenServer.call(__MODULE__, :checkout)
    end

    # Chicken'n *BAWK*
    def chicken(worker_pid) do
        GenServer.cast(__MODULE__, {:checkin, worker_pid})
    end

    # --------- Callbacks ---------- #

    # Invoked when Genserver.start_link/3 is called
    def init([sup, pool_config]) when is_pid(sup) do
        monitors = :ets.new(:monitors, [:private])
        init(pool_config, %State{sup: sup, monitors: monitors})
    end

    # Pattern matches mfa option
    def init([{:mfa, mfa}|rest], state) do
        init(rest, %{state | mfa: mfa})
    end

    # Pattern matches size option
    def init([{:size, size}|rest], state) do
        init(rest, %{state | size: size})
    end

    # Ignores all other options
    def init([_|rest], state) do
        init(rest, state)
    end

    # Base case when options is empty
    def init([], state) do
        send(self, :start_worker_supervisor)
        {:ok, state}
    end

    def handle_info(:start_worker_supervisor, state = %{sup: sup, mfa: mfa, size: size}) do
        {:ok, worker_sup} = Supervisor.start_child(sup, supervisor_spec(mfa))
        workers = prepopulate(size, worker_sup)
        {:noreply, %{state | worker_sup: worker_sup, workers: workers}}
    end

    def handle_call(:checkout, (from_pid, _ref). %{workers: workers, monitors: monitors} = state) do
        case workers do
            [worker|rest] ->
                ref = Process.monitor(from_pid)
                true = :ets.insert(monitors, {worker, ref})
                {:reply, worker, %{state | workers: rest}}

            [] ->
                {:reply, :noproc, state}
        end
    end

    # ----- Private Functions ------ #

    defp supervisor_spec(mfa) do
        opts = [restart: :temporary]
        supervisor(Pooly.WorkerSupervisor, [mfa], opts)
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
end


