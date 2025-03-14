defmodule Todo.Cache do
  @moduledoc """
  There should be only 1 cache process running, so we use `name: __MODULE__`.
  This spawns numerous Todo.Server processes, so they DON'T use the module name internally
  """
  use GenServer

  @impl GenServer
  def init(start_db \\ true) do
    if start_db do
      {:ok, _} = Todo.Database.start()
    end

    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:server_process, todo_list_name}, _, todo_servers) do
    case Map.fetch(todo_servers, todo_list_name) do
      {:ok, todo_server} ->
        # Check if the process is still alive
        if Process.alive?(todo_server) do
          {:reply, todo_server, todo_servers}
        else
          # Process has crashed, create a new one
          {:ok, new_server} = Todo.Server.start(todo_list_name)

          {
            :reply,
            new_server,
            Map.put(todo_servers, todo_list_name, new_server)
          }
        end

      :error ->
        {:ok, new_server} = Todo.Server.start(todo_list_name)

        {
          :reply,
          new_server,
          Map.put(todo_servers, todo_list_name, new_server)
        }
    end
  end

  def start(start_db \\ true) do
    GenServer.start(__MODULE__, start_db, name: __MODULE__)
  end

  def server_process(todo_list_name) do
    GenServer.call(__MODULE__, {:server_process, todo_list_name})
  end
end
