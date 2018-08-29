defmodule Pooly.WorkerSupervisor do
    use Supervisor

    # ------------- API -------------#

    def start_link(pool_server, {_,_,_} = mfa) do
        Supervisor.start_link(__MODULE__, [pool_server, mfa])
    end

    # --------- Callbacks ---------- #

    def init([pool_server, {m,f,a}]) do
        Process.link(pool_server)

        # If a worker fails, always restart with function f
        worker_opts = [restart: :permanent,
                       shutdown: 5000,
                       function: f]
        
        # A list of child processes (the workers)
        children = [worker(m, a, worker_opts)]
 
        # :one_for_one: Only the process that died is restarted
        # :one_for_all: All processes in the supervision tree are killed then restarted
        # :rest_for_one: Only the process that died and the processes spawned after the dead one are restarted
        # :simple_one_for_one: Allows us to create identical processes dynamically for the supervisor 

        # What the supervisor should look like/how it should act
        opts = [strategy: :simple_one_for_one,
                max_restarts: 5,
                max_secodns: 5]
        # Helper function to create children specs (a recipe to spawn children)
        supervise(children, opts)
    end
end