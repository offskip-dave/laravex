defmodule Tests.Unit.ResourceCollectionTest do
  use ExUnit.Case, async: true

  defmodule UserResource do
    use Laravex.Http.Resource

    def to_map(user), do: %{id: user.id, name: user.name}
  end

  defmodule UserCollection do
    use Laravex.Http.ResourceCollection, collects: Tests.Unit.ResourceCollectionTest.UserResource

    def additional(_resources), do: %{meta: %{source: "named"}}
  end

  test "anonymous collection wraps list" do
    users = [%{id: 1, name: "Ada"}, %{id: 2, name: "Grace"}]
    coll = UserResource.collection(users)

    assert %Laravex.Http.ResourceCollection{collects: UserResource} = coll

    resp = Laravex.Http.ResourceCollection.response(coll)
    assert {:ok, body} = Laravex.Support.JSON.decode(resp.body)
    assert body["data"] == [%{"id" => 1, "name" => "Ada"}, %{"id" => 2, "name" => "Grace"}]
  end

  test "named collection make/1 merges additional" do
    users = [%{id: 1, name: "Ada"}]
    resp = UserCollection.make(users)
    assert {:ok, body} = Laravex.Support.JSON.decode(resp.body)

    assert body["data"] == [%{"id" => 1, "name" => "Ada"}]
    assert body["meta"]["source"] == "named"
  end

  test "collection_response paginator includes links and meta" do
    page = %{
      data: [%{id: 1, name: "Ada"}],
      total: 1,
      per_page: 15,
      current_page: 1,
      path: "/users"
    }

    resp = UserResource.collection_response(page)
    assert {:ok, body} = Laravex.Support.JSON.decode(resp.body)

    assert body["data"] == [%{"id" => 1, "name" => "Ada"}]
    assert is_map(body["links"])
    assert body["meta"]["total"] == 1
    assert body["meta"]["current_page"] == 1
  end

  test "when_cond strips missing values via merge" do
    attrs =
      Laravex.Http.Resource.merge(%{
        id: 1,
        secret: Laravex.Http.Resource.when_cond(false, "nope"),
        name: Laravex.Http.Resource.when_cond(true, "Ada")
      })

    assert attrs == %{id: 1, name: "Ada"}
  end
end
