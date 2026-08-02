defmodule DSpace.API.Model.ResourceUpdateTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias DSpace.API.Model.ResourceUpdate

  describe "new/1" do
    test "accepts a list and rejects unknown operations" do
      list = [op: "copy", path: "/foo"]

      assert_raise FunctionClauseError, fn ->
        ResourceUpdate.new(list)
      end
    end

    test "requires a path" do
      map = %{op: :add, value: "foo"}

      assert_raise ArgumentError, fn ->
        ResourceUpdate.new(map)
      end
    end
  end

  describe "wire format conversion" do
    property "to_map/1 and from_map/1 round-trips" do
      # to_map direction with a struct generator since an update is a payload and
      # not taken *from* the wire
      check all(value <- struct_generator()) do
        wire =
          value
          |> ResourceUpdate.to_map()
          |> JSON.encode!()

        reconstructed =
          wire
          |> JSON.decode!()
          |> ResourceUpdate.from_map()

        assert reconstructed == value
      end
    end

    property "to_map/1 omits nil optional fields" do
      check all(value <- struct_generator(), max_runs: 10) do
        map = ResourceUpdate.to_map(value)

        if value.value == nil, do: refute(Map.has_key?(map, "value"))
        if value.from == nil, do: refute(Map.has_key?(map, "from"))
      end
    end

    test "from_map/1 treats absent optional fields as nil" do
      map = %{"op" => "add", "path" => "/foo"}
      result = ResourceUpdate.from_map(map)

      assert result.value == nil
      assert result.from == nil
    end

    test "from_map/1 rejects unknown operations" do
      map = %{"op" => "copy", "path" => "/foo"}

      assert_raise FunctionClauseError, fn ->
        ResourceUpdate.from_map(map)
      end
    end
  end

  # Private helpers

  defp struct_generator do
    gen all(
          op <- member_of([:add, :remove, :replace, :move]),
          path <- string(:printable),
          value <- one_of([constant(nil), string(:printable)]),
          from <- one_of([constant(nil), string(:printable)])
        ) do
      %ResourceUpdate{
        op: op,
        path: path,
        value: value,
        from: from
      }
    end
  end
end
