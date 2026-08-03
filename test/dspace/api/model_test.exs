defmodule DSpace.API.ModelTest do
  use ExUnit.Case, async: true

  alias DSpace.API.Model
  alias DSpace.API.ModelTest.ModelA
  alias DSpace.API.ModelTest.ModelB
  alias DSpace.API.ModelTest.ModelC

  # Some tests in these module indeed don't call any library code directly, but verify the macro
  # provides the expected behavior and implementations for standard library functionality
  # credo:disable-for-this-file Jump.CredoChecks.VacuousTest

  defmodule ModelA do
    @moduledoc false
    use Model

    @wire %{snake_case: "camelCase"}

    defstruct snake_case: "bar",
              baz: "qux",
              qux: nil

    @impl true
    def from_map(%{"camelCase" => foo, "baz" => baz, "qux" => qux}) do
      %__MODULE__{snake_case: foo, baz: baz, qux: qux}
    end
  end

  defmodule ModelB do
    @moduledoc false
    use Model

    @wire %{}

    defstruct model: %ModelA{},
              baz: "qux"

    @impl true
    def from_map(%{"model" => model, "baz" => baz}) do
      %__MODULE__{model: model, baz: baz}
    end

    @impl true
    def to_map(%__MODULE__{model: model, baz: _baz}) do
      %{"model" => model}
    end
  end

  defmodule ModelC do
    @moduledoc false
    use Model,
      drop_nil_on_wire: false

    @wire %{snake_case: "camelCase"}

    defstruct snake_case: "bar",
              baz: nil

    @impl true
    def from_map(%{"camelCase" => foo, "baz" => baz}) do
      %__MODULE__{snake_case: foo, baz: baz}
    end
  end

  test "to_map/1 uses @wire map to convert, and drops nil values by default" do
    model = struct(ModelA)

    map = ModelA.to_map(model)

    assert map == %{"camelCase" => "bar", "baz" => "qux"}
    refute map == %{"camelCase" => "bar", "baz" => "qux", "qux" => nil}
  end

  test "to_map/1 respects drop_nil_on_wire option when set to false" do
    model = struct(ModelC)

    map = ModelC.to_map(model)

    assert map == %{"camelCase" => "bar", "baz" => nil}
    refute map == %{"camelCase" => "bar"}
  end

  test "encoding uses overridden to_map/1 function and handles struct values" do
    model = struct(ModelB)

    json = JSON.encode!(model)

    assert json == ~s({"model":{"baz":"qux","camelCase":"bar"}})
    refute json == ~s({"model":{"baz":"qux","camelCase":"bar"}},"baz":"qux")
  end

  test "macro provides a JSON.Encoder implementation" do
    assert JSON.Encoder.impl_for(%ModelA{})
  end

  test "macro provides a Jason.Encoder implementation when Jason is available" do
    # Jason is available, transitive dependency (Req)
    assert Jason.Encoder.impl_for(%ModelA{})
  end
end
