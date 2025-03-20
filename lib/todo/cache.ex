defmodule Todo.Cache do
  @moduledoc """
  There should be only 1 cache process running, so we use `name: __MODULE__`.
  This spawns numerous Todo.Server processes, so they DON'T use the module name internally
  """
  use GenServer

  def start_link do
    IO.puts("Starting Todo Cache.")

    DynamicSupervisor.start_link(
      name: __MODULE__,
      strategy: :one_for_one
    )
  end

  def child_spec(_arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :supervisor
    }
  end

  def server_process(todo_list_name) do
    case start_child(todo_list_name) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end

  defp start_child(todo_list_name) do
    DynamicSupervisor.start_child(
      __MODULE__,
      {Todo.Server, todo_list_name}
    )
  end

  @impl GenServer
  def init(_) do
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
          {:ok, new_server} = Todo.Server.start_link(todo_list_name)

          {
            :reply,
            new_server,
            Map.put(todo_servers, todo_list_name, new_server)
          }
        end

      :error ->
        {:ok, new_server} = Todo.Server.start_link(todo_list_name)

        {
          :reply,
          new_server,
          Map.put(todo_servers, todo_list_name, new_server)
        }
    end
  end
end
