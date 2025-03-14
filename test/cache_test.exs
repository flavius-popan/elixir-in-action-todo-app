defmodule Todo.CacheTest do
  use ExUnit.Case

  setup do
    # Ensure the cache process is stopped before each test
    Process.whereis(Todo.Cache) && GenServer.stop(Todo.Cache)

    # Start a fresh cache for each test with database start disabled
    {:ok, _cache_pid} = Todo.Cache.start(_start_db = false)

    on_exit(fn ->
      # Clean up after test
      Process.whereis(Todo.Cache) && GenServer.stop(Todo.Cache)
    end)
  end

  test "server_process returns the same PID for the same list name" do
    # Get a server process for a specific list name
    first_pid = Todo.Cache.server_process("shopping")

    # Request the same list name again
    second_pid = Todo.Cache.server_process("shopping")

    # Should be the same PID
    assert first_pid == second_pid
  end

  test "server_process returns different PIDs for different list names" do
    # Get server processes for different list names
    shopping_pid = Todo.Cache.server_process("shopping")
    work_pid = Todo.Cache.server_process("work")

    # Should be different PIDs
    refute shopping_pid == work_pid
  end

  test "cache state contains the server process" do
    # Get a server process
    list_name = "shopping"
    server_pid = Todo.Cache.server_process(list_name)

    # Get the cache state
    cache_state = :sys.get_state(Todo.Cache)

    # Verify the state contains our server process
    assert Map.get(cache_state, list_name) == server_pid
  end

  test "creating multiple server processes" do
    # Create a list of different todo list names
    list_names = ["shopping", "work", "hobby", "family", "travel"]

    # Get a server process for each list name
    pids = Enum.map(list_names, &Todo.Cache.server_process/1)

    # All PIDs should be unique
    assert length(Enum.uniq(pids)) == length(list_names)

    # Requesting the same names again should return the same PIDs
    new_pids = Enum.map(list_names, &Todo.Cache.server_process/1)
    assert pids == new_pids

    # Check the cache state
    cache_state = :sys.get_state(Todo.Cache)

    # Verify all server processes are in the state
    Enum.each(list_names, fn name ->
      assert Map.get(cache_state, name) in pids
    end)
  end

  test "server process is reused if it exists" do
    # Get a server process
    list_name = "important_list"
    first_pid = Todo.Cache.server_process(list_name)

    # Get the cache state and verify it contains our server
    cache_state = :sys.get_state(Todo.Cache)
    assert Map.get(cache_state, list_name) == first_pid

    # Request the same list name again
    second_pid = Todo.Cache.server_process(list_name)

    # Should be the same PID
    assert first_pid == second_pid

    # The state should remain unchanged
    new_cache_state = :sys.get_state(Todo.Cache)
    assert new_cache_state == cache_state
  end

  test "new server process is created if the previous one has crashed" do
    # Get a server process
    list_name = "crash_test_list"
    first_pid = Todo.Cache.server_process(list_name)

    # Verify it's in the cache state
    cache_state = :sys.get_state(Todo.Cache)
    assert Map.get(cache_state, list_name) == first_pid

    # Simulate the server process crashing
    Process.exit(first_pid, :kill)

    # Wait a bit to ensure the process is dead
    Process.sleep(10)
    refute Process.alive?(first_pid)

    # Request a server for the same list name
    second_pid = Todo.Cache.server_process(list_name)

    # Should be a different PID since the original crashed
    refute first_pid == second_pid

    # The new PID should be in the cache state
    new_cache_state = :sys.get_state(Todo.Cache)
    assert Map.get(new_cache_state, list_name) == second_pid
  end
end
