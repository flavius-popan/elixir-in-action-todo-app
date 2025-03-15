defmodule Todo.Database do
  alias Todo.DatabaseWorker
  use GenServer

  @default_db_folder "./persist"

  def start_link(db_folder \\ @default_db_folder) do
    GenServer.start_link(__MODULE__, db_folder, name: __MODULE__)
  end

  def store(list_name, data) do
    GenServer.cast(__MODULE__, {:store, list_name, data})
  end

  def get(list_name) do
    GenServer.call(__MODULE__, {:get, list_name})
  end

  def choose_worker(list_name) do
    :erlang.phash2(list_name, 3)
  end

  @impl GenServer
  def init(db_folder) do
    IO.puts("Starting ToDo Database.")

    worker_pool =
      Enum.map(0..2, fn i -> {i, elem(Todo.DatabaseWorker.start_link(db_folder), 1)} end)
      |> Map.new()

    {:ok, worker_pool}
  end

  @impl GenServer
  def handle_cast({:store, list_name, data}, worker_pool) do
    worker_pid = worker_pool[choose_worker(list_name)]
    DatabaseWorker.store(worker_pid, list_name, data)
    {:noreply, worker_pool}
  end

  @impl GenServer
  def handle_call({:get, list_name}, _caller, worker_pool) do
    worker_pid = worker_pool[choose_worker(list_name)]
    data = DatabaseWorker.get(worker_pid, list_name)
    {:reply, data, worker_pool}
  end
end

defmodule Todo.DatabaseWorker do
  use GenServer

  def start_link(db_folder) do
    GenServer.start_link(__MODULE__, db_folder)
  end

  def store(worker_pid, list_name, data) do
    GenServer.cast(worker_pid, {:store, list_name, data})
  end

  def get(worker_pid, list_name) do
    GenServer.call(worker_pid, {:get, list_name})
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
