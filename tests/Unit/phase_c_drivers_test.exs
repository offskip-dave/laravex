defmodule Tests.Unit.PhaseCDriversTest do
  use ExUnit.Case, async: true

  alias Laravex.Database.Query
  alias Laravex.Pipeline

  test "database resolver maps adapters" do
    assert Laravex.Database.Resolver.module("sqlite") == Laravex.Database.Adapters.Sqlite
    assert Laravex.Database.Resolver.module("pgsql") == Laravex.Database.Adapters.Postgres
    assert Laravex.Database.Resolver.module("postgres") == Laravex.Database.Adapters.Postgres
    assert Laravex.Database.Resolver.module("mysql") == Laravex.Database.Adapters.Mysql
    assert Laravex.Database.Resolver.module("mariadb") == Laravex.Database.Adapters.Mysql
  end

  test "union sql wraps branches" do
    left = Query.table("users") |> Query.select(["id"])
    right = Query.table("posts") |> Query.select(["id"])
    sql = Query.to_sql(Query.union(left, right))

    assert sql =~ "FROM users"
    assert sql =~ "FROM posts"
    assert sql =~ " UNION "
    assert sql =~ "(SELECT"
  end

  test "in_random_order uses sqlite random fragment by default" do
    sql =
      Query.table("users")
      |> Query.in_random_order()
      |> Query.to_sql()

    assert sql =~ "RANDOM()"
  end

  test "pipeline runs and halts" do
    result =
      Pipeline.send(1)
      |> Pipeline.through([
        fn n -> n + 1 end,
        fn n -> {:halt, n * 2} end,
        fn n -> n + 100 end
      ])
      |> Pipeline.then(fn v -> v end)

    assert result == 4
  end

  test "optional service resolvers accept new drivers" do
    assert Laravex.Cache.Resolver.module("redis") == Laravex.Cache.Stores.Redis
    assert Laravex.Session.Resolver.module() in [
             Laravex.Session.Drivers.File,
             Laravex.Session.Drivers.Database,
             Laravex.Session.Drivers.Redis
           ]
    assert Laravex.Mail.Resolver.module("smtp") == Laravex.Mail.Transports.Smtp
    assert Laravex.Filesystem.Resolver.module(%{"driver" => "s3"}) == Laravex.Filesystem.Disks.S3
    assert Laravex.Broadcasting.Resolver.module("pubsub") == Laravex.Broadcasting.Drivers.Pubsub
    assert Laravex.Queue.Resolver.module("redis") == Laravex.Queue.Connections.Redis
  end
end
