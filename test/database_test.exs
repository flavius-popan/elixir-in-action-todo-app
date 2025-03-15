defmodule Todo.DatabaseTest do
  use ExUnit.Case

  @test_db_folder "./test_persist"

  setup do
    # Clean up any existing test folder
    File.rm_rf!(@test_db_folder)
    File.mkdir_p!(@test_db_folder)

    # Ensure the database process is stopped before each test
    Process.whereis(Todo.Database) && GenServer.stop(Todo.Database)

    on_exit(fn ->
      # Clean up test folder after tests
      File.rm_rf!(@test_db_folder)
      # Ensure the database process is stopped after each test
      Process.whereis(Todo.Database) && GenServer.stop(Todo.Database)
    end)

    :ok
  end

  describe "Todo.Database" do
    test "start creates a pool of worker processes" do
      # Start the database with a test folder
      {:ok, _} = Todo.Database.start_link(@test_db_folder)

      # Get the state to verify worker pool
      state = :sys.get_state(Todo.Database)

      # Verify we have 3 workers (0, 1, 2)
      assert map_size(state) == 3
      assert is_pid(state[0])
      assert is_pid(state[1])
      assert is_pid(state[2])

      # Verify all workers are alive
      Enum.each(state, fn {_, pid} ->
        assert Process.alive?(pid)
      end)

      # Clean up
      GenServer.stop(Todo.Database)
    end

    test "choose_worker consistently maps the same key to the same worker" do
      # Same key should always map to the same worker
      key = "test_key"
      worker_id = Todo.Database.choose_worker(key)

      # Test multiple times to ensure consistency
      for _ <- 1..10 do
        assert Todo.Database.choose_worker(key) == worker_id
      end

      # Different keys might map to different workers
      different_keys = ["another_key", "yet_another_key", "one_more_key"]

      different_worker_ids =
        Enum.map(different_keys, fn key ->
          Todo.Database.choose_worker(key)
        end)

      # At least one key should map to a different worker
      assert Enum.count(Enum.uniq(different_worker_ids)) > 1 ||
               worker_id not in different_worker_ids
    end

    test "store and get operations work correctly" do
      # Start the database with a test folder
      {:ok, _} = Todo.Database.start_link(@test_db_folder)

      # Store some data
      test_key = "test_list"
      test_data = %{title: "Test Data"}

      Todo.Database.store(test_key, test_data)

      # Allow time for async operations to complete
      Process.sleep(100)

      # Verify data was stored and can be retrieved
      assert Todo.Database.get(test_key) == test_data

      # Test with another key/data pair
      another_key = "another_list"
      another_data = %{title: "Another Test"}

      Todo.Database.store(another_key, another_data)
      Process.sleep(100)

      assert Todo.Database.get(another_key) == another_data

      # Original data should still be available
      assert Todo.Database.get(test_key) == test_data

      # Clean up
      GenServer.stop(Todo.Database)
    end

    test "get returns nil for non-existent keys" do
      # Start the database with a test folder
      {:ok, _} = Todo.Database.start_link(@test_db_folder)

      assert Todo.Database.get("non_existent_key") == nil

      # Clean up
      GenServer.stop(Todo.Database)
    end
  end

  describe "Todo.DatabaseWorker" do
    test "start creates the database folder if it doesn't exist" do
      test_folder = Path.join(@test_db_folder, "subfolder")

      # Ensure folder doesn't exist
      File.rm_rf!(test_folder)
      refute File.exists?(test_folder)

      # Start worker
      {:ok, _} = Todo.DatabaseWorker.start_link(test_folder)

      # Verify folder was created
      assert File.exists?(test_folder)
    end

    test "store writes data to a file" do
      {:ok, worker_pid} = Todo.DatabaseWorker.start_link(@test_db_folder)

      test_key = "test_key"
      test_data = %{title: "Test Data"}

      # Store data
      Todo.DatabaseWorker.store(worker_pid, test_key, test_data)

      # Allow time for async operation to complete
      Process.sleep(100)

      # Verify file exists
      file_path = Path.join(@test_db_folder, to_string(test_key))
      assert File.exists?(file_path)

      # Verify file content
      {:ok, binary_data} = File.read(file_path)
      assert :erlang.binary_to_term(binary_data) == test_data
    end

    test "get reads data from a file" do
      {:ok, worker_pid} = Todo.DatabaseWorker.start_link(@test_db_folder)

      test_key = "test_key"
      test_data = %{title: "Test Data"}

      # Store data
      Todo.DatabaseWorker.store(worker_pid, test_key, test_data)

      # Allow time for async operation to complete
      Process.sleep(100)

      # Retrieve data
      retrieved_data = Todo.DatabaseWorker.get(worker_pid, test_key)

      # Verify data
      assert retrieved_data == test_data
    end

    test "get returns nil for non-existent keys" do
      {:ok, worker_pid} = Todo.DatabaseWorker.start_link(@test_db_folder)

      assert Todo.DatabaseWorker.get(worker_pid, "non_existent_key") == nil
    end

    test "operations are performed asynchronously" do
      {:ok, worker_pid} = Todo.DatabaseWorker.start_link(@test_db_folder)

      test_key = "async_test"
      test_data = %{title: "Async Test"}

      # Monitor the worker process
      ref = Process.monitor(worker_pid)

      # Store should return immediately (cast)
      start_time = System.monotonic_time(:millisecond)
      Todo.DatabaseWorker.store(worker_pid, test_key, test_data)
      end_time = System.monotonic_time(:millisecond)

      # Operation should return quickly
      assert end_time - start_time < 50

      # Worker should not have crashed
      receive do
        {:DOWN, ^ref, :process, ^worker_pid, _} ->
          flunk("Worker process crashed unexpectedly")
      after
        0 -> :ok
      end

      # Verify the file doesn't exist immediately (proving it's async)
      file_path = Path.join(@test_db_folder, to_string(test_key))

      if File.exists?(file_path) do
        file_info = File.stat!(file_path)
        # If file exists, it should be empty or incomplete
        assert file_info.size == 0
      end

      # Wait for the async operation to complete
      Process.sleep(100)

      # Now the file should exist with the correct data
      assert File.exists?(file_path)
      {:ok, binary_data} = File.read(file_path)
      assert :erlang.binary_to_term(binary_data) == test_data

      # Get should also be async (even though it's a call)
      task =
        Task.async(fn ->
          Todo.DatabaseWorker.get(worker_pid, test_key)
        end)

      # The result should eventually be available
      assert Task.await(task) == test_data
    end
  end

  describe "Integration tests" do
    test "end-to-end persistence" do
      # Start the database with a test folder
      {:ok, _} = Todo.Database.start_link(@test_db_folder)

      # Store some data
      test_key = "integration_test"
      test_data = %{title: "Integration Test"}

      Todo.Database.store(test_key, test_data)

      # Allow time for async operations to complete
      Process.sleep(100)

      # Verify data was stored
      assert Todo.Database.get(test_key) == test_data

      # Get the worker pool from the database state
      worker_pool = :sys.get_state(Todo.Database)

      # Get the worker that would handle this key
      worker_id = Todo.Database.choose_worker(test_key)
      _worker_pid = worker_pool[worker_id]

      # Verify file exists in the worker's folder
      file_path = Path.join(@test_db_folder, to_string(test_key))
      assert File.exists?(file_path)

      # Verify file content
      {:ok, binary_data} = File.read(file_path)
      assert :erlang.binary_to_term(binary_data) == test_data

      # Clean up
      GenServer.stop(Todo.Database)
    end

    test "persistence across process restarts" do
      # Start the database with a test folder
      {:ok, _} = Todo.Database.start_link(@test_db_folder)

      # Store some data
      test_key = "restart_test"
      test_data = %{title: "Restart Test"}

      Todo.Database.store(test_key, test_data)

      # Allow time for async operations to complete
      Process.sleep(100)

      # Stop the database
      GenServer.stop(Todo.Database)
      # Give it time to shut down
      Process.sleep(50)

      # Start a new database instance
      {:ok, _} = Todo.Database.start_link(@test_db_folder)

      # Data should still be retrievable
      assert Todo.Database.get(test_key) == test_data

      # Clean up
      GenServer.stop(Todo.Database)
    end

    test "multiple concurrent operations" do
      # Start the database with a test folder
      {:ok, _} = Todo.Database.start_link(@test_db_folder)

      # Perform multiple concurrent operations
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            key = "concurrent_#{i}"
            data = %{title: "Concurrent Test #{i}"}

            Todo.Database.store(key, data)
            # Small delay to ensure some overlap
            Process.sleep(10)
            Todo.Database.get(key)
          end)
        end

      # Wait for all tasks to complete
      results = Task.await_many(tasks, 5000)

      # Verify all operations completed successfully
      for {result, i} <- Enum.with_index(results, 1) do
        assert result == %{title: "Concurrent Test #{i}"}
      end

      # Clean up
      GenServer.stop(Todo.Database)
    end
  end
end
