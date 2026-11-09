defmodule Tests.Unit.IlluminateDepthTest do
  use ExUnit.Case, async: true

  test "multi-db using_connection restores previous name" do
    prev = Laravex.Database.Connection.current_name()

    Laravex.Database.Connection.using_connection("sqlite", fn ->
      assert Laravex.Database.Connection.current_name() == "sqlite"
    end)

    assert Laravex.Database.Connection.current_name() == prev
  end

  test "query connection/2 sets connection field" do
    q = Laravex.Database.Query.table("users") |> Laravex.Database.Query.connection("sqlite")
    assert q.connection == "sqlite"
  end

  test "LazyCollection map/take" do
    result =
      Laravex.Support.LazyCollection.make(1..10)
      |> Laravex.Support.LazyCollection.map(&(&1 * 2))
      |> Laravex.Support.LazyCollection.take(3)
      |> Laravex.Support.LazyCollection.to_list()

    assert result == [2, 4, 6]
  end

  test "Concurrency.run executes tasks" do
    assert Laravex.Concurrency.run([fn -> 1 end, fn -> 2 end]) == [1, 2]
  end

  test "Process.fake intercepts commands" do
    Laravex.Process.fake(fn _cmd -> %{exit_code: 0, output: "ok", error: ""} end)
    result = Laravex.Process.run(["echo", "hi"])
    assert result.successful?
    assert result.output == "ok"
    Laravex.Process.fake_clear()
  end

  test "Pennant activate/active?" do
    Laravex.Pennant.activate("feature-x")
    assert Laravex.Pennant.active?("feature-x")
    Laravex.Pennant.deactivate("feature-x")
    refute Laravex.Pennant.active?("feature-x")
  end

  test "cookie session seal/open roundtrip" do
    sealed = Laravex.Session.Drivers.Cookie.seal(%{"user_id" => 1, "_sid" => "abc"})
    opened = Laravex.Session.Drivers.Cookie.open(sealed)
    assert opened["user_id"] == 1
    assert opened["_sid"] == "abc"
  end

  test "Macroable registers macros on Collection" do
    Laravex.Support.Collection.macro(:double_count, fn %Laravex.Support.Collection{} = c ->
      Laravex.Support.Collection.count(c) * 2
    end)

    assert Laravex.Support.Collection.has_macro?(:double_count)
  end

  test "RedisCluster slot is stable" do
    s1 = Laravex.Support.RedisCluster.slot("user:1")
    s2 = Laravex.Support.RedisCluster.slot("user:1")
    assert s1 == s2
    assert s1 >= 0 and s1 < 16_384
  end

  test "resolver maps sqlsrv to native TDS adapter" do
    assert Laravex.Database.Resolver.module("sqlsrv") ==
             Laravex.Database.Adapters.Native.SqlServer
  end
end
