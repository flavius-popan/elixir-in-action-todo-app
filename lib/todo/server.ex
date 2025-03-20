defmodule Todo.Server do
  @moduledoc """
  Split init with non-blocking return, followed by DB call in handle_continue()
  """
  use GenServer, restart: :temporary

  def start_link(list_name) do
    GenServer.start_link(__MODULE__, list_name, name: via_tuple(list_name))
  end

  defp via_tuple(list_name) do
    Todo.ProcessRegistry.via_tuple({__MODULE__, list_name})
  end

  def add_entry(server_pid, entry) do
    GenServer.cast(server_pid, {:add, entry})
  end

  def entries(server_pid, date) do
    GenServer.call(server_pid, {:entries, date})
  end

  @impl GenServer
  def init(name) do
    IO.puts("Starting ToDo Server for #{name}")
    {:ok, {name, nil}, {:continue, :init}}
  end

  @impl GenServer
  def handle_continue(:init, {name, nil}) do
    todo_list =
      if Process.whereis(Todo.Database) do
        Todo.Database.get(name) || Todo.List.new()
      else
        Todo.List.new()
      end

    {:noreply, {name, todo_list}}
  end

  @impl GenServer
  def handle_cast({:add, entry}, {name, todo_list}) do
    new_list = Todo.List.add_entry(todo_list, entry)

    if Process.whereis(Todo.Database) do
      Todo.Database.store(name, new_list)
    end

    {:noreply, {name, new_list}}
  end

  @impl GenServer
  def handle_call({:entries, date}, _from, {name, todo_list}) do
    {:reply, Todo.List.entries(todo_list, date), {name, todo_list}}
  end
end
