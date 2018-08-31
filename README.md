# Pooly
An exercise from the wonderful book "The Little Elixir & OTP Guidebook" (Chp. 7), Pooly is a worker pool library that can manage basic worker checkin/outs, multiple pools, and queuing. 

## Ways to Play
### Queues
  - To test out the V3** clone the repository and `iex -S mix` inside the repo. (You can edit the pool config inside of lib/pooly.ex)
  - In iex you can checkout workers like this `w1 = Pooly.checkout("Pool1")`
  - Checkout out up to 3 workers (as per the default pool_config) in Pool1
  - Tell one of the workers to "work" for 10 seconds `SampleWorker.work_for(w1, 10_000)`
  - Queue up a worker `Pooly.checkout("Pool1", true, :infinity)` and in ~10 seconds a PID of the newly checked out worker should be returned. IEX will be blocked until a worker is made available as we set the block timeout to "infinity"

### Observer
  - To test out the supervision functionality run `iex -S mix` inside the repo.
  - Enter `:observer.start`
  - Once the Observer GUI appears navigate to the "applications" tab, you will be able to observer the hierarchy of running processes.
  - Play around by killing some workers (untagged pids to the far right), worker supervisors (untagged pids adjacent to Pool#Servers), PoolSupervisors, or even the PoolsSupervisor! 

\** There are 4 versions in the book, but I boiled it down to 3.
