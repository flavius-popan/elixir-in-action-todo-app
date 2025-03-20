defmodule Todo.Database do
  @pool_size 3
  @default_db_folder "./persist"

  def start_link do
    IO.puts("Starting Database Server.")
    File.mkdir_p!(@default_db_folder)

    children = Enum.map(1..@pool_size, &worker_spec/1)
    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp worker_spec(worker_id) do
    default_worker_spec = {Todo.DatabaseWorker, {@default_db_folder, worker_id}}
    Supervisor.child_spec(default_worker_spec, id: worker_id)
  end

  def child_spec(_) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :supervisor
    }
  end

  def store(list_name, data) do
    list_name
    |> choose_worker()
    |> Todo.DatabaseWorker.store(list_name, data)
  end

  def get(list_name) do
    list_name
    |> choose_worker()
    |> Todo.DatabaseWorker.get(list_name)
  end

  defp choose_worker(list_name) do
    :erlang.phash2(list_name, @pool_size) + 1
  end
end

defmodule Todo.DatabaseWorker do
  use GenServer

  def start_link({db_folder, worker_id}) do
    GenServer.start_link(
      __MODULE__,
      db_folder,
      name: via_tuple(worker_id)
    )
  end

  defp via_tuple(worker_id) do
    Todo.ProcessRegistry.via_tuple({__MODULE__, worker_id})
  end

  def store(worker_pid, list_name, data) do
    GenServer.cast(via_tuple(worker_pid), {:store, list_name, data})
  end

  def get(worker_pid, list_name) do
    GenServer.call(via_tuple(worker_pid), {:get, list_name})
  end

  @impl GenServer
  def init(db_folder) do
    IO.puts("Starting ToDo Database Worker.")
    File.mkdir_p!(db_folder)
    {:ok, db_folder}
  end

  @impl GenServer
  def handle_cast({:store, list_name, data}, db_folder) do
    spawn(fn ->
      list_name
      |> file_name(db_folder)
      |> File.write!(:erlang.term_to_binary(data))
    end)

    {:noreply, db_folder}
  end

  @impl GenServer
  def handle_call({:get, list_name}, caller, db_folder) do
    spawn(fn ->
      data =
        case File.read(file_name(list_name, db_folder)) do
          {:ok, contents} -> :erlang.binary_to_term(contents)
          _ -> nil
        end

      GenServer.reply(caller, data)
    end)

    {:noreply, db_folder}
  end

  defp file_name(list_name, db_folder) do
    Path.join(db_folder, to_string(list_name))
  end
end
