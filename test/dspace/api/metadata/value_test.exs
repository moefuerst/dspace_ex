defmodule DSpace.API.Metadata.ValueTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias DSpace.API.Metadata.Value

  doctest Value

  describe "new/2" do
    property "new/2 applies valid options" do
      check all(
              v <- binary(),
              language <- one_of([constant(nil), binary()]),
              authority <- one_of([constant(nil), binary()]),
              confidence <-
                one_of([
                  constant(:accepted),
                  constant(:uncertain),
                  constant(:ambiguous),
                  constant(:not_found),
                  constant(:failed),
                  constant(:rejected),
                  constant(:no_value),
                  constant(:unset)
                ]),
              security_level <-
                one_of([constant(:public), constant(:trusted), constant(:admin_owner)])
            ) do
        opts =
          Enum.reject(
            [
              language: language,
              authority: authority,
              confidence: confidence,
              security_level: security_level
            ],
            fn {_k, v} -> is_nil(v) end
          )

        result = Value.new(v, opts)

        assert result.value == v
        assert result.confidence == confidence
        assert result.security_level == security_level
        if language, do: assert(result.language == language)
        if authority, do: assert(result.authority == authority)
      end
    end

    test "raises ArgumentError on unrecognized option key" do
      assert_raise ArgumentError, fn ->
        Value.new("test", invalid_key: "value")
      end
    end

    test "invalid confidence_score atom is accepted at construction, fails at serialization" do
      value = Value.new("test", confidence: :bogus)

      assert value.confidence == :bogus
      assert_raise FunctionClauseError, fn -> Value.to_map(value) end
    end

    test "integer confidence instead of atom is accepted at construction, fails at serialization" do
      value = Value.new("test", confidence: 600)

      assert value.confidence == 600
      assert_raise FunctionClauseError, fn -> Value.to_map(value) end
    end

    test "integer security_level instead of atom is accepted at construction, fails at serialization" do
      value = Value.new("test", security_level: 0)

      assert value.security_level == 0
      assert_raise FunctionClauseError, fn -> Value.to_map(value) end
    end

    test "invalid security_level atom is accepted at construction, fails at serialization" do
      value = Value.new("test", security_level: :secret)

      assert value.security_level == :secret
      assert_raise FunctionClauseError, fn -> Value.to_map(value) end
    end

    test "confidence: nil is equivalent to omitting the option" do
      # nil confidence is a deserialization artifact (from_map with "confidence": null)
      assert Value.new("x", confidence: nil).confidence == :unset
    end
  end

  describe "relation/2" do
    property "relation/2 constructs Value struct" do
      check all(
              display <- binary(min_length: 1),
              authority <- binary(min_length: 1)
            ) do
        result = Value.relation(display, authority)

        assert result.value == display
        assert result.authority == authority
        assert result.confidence == :uncertain
        assert result.language == nil
        assert result.place == nil
        assert result.security_level == nil
      end
    end

    test "raises FunctionClauseError on empty string authority" do
      assert_raise FunctionClauseError, fn ->
        Value.relation("display", "")
      end
    end

    test "raises FunctionClauseError on empty string display value" do
      assert_raise FunctionClauseError, fn ->
        Value.relation("", "uuid")
      end
    end
  end

  describe "relation/3" do
    property "relation/3 applies valid options" do
      check all(
              display <- binary(min_length: 1),
              authority <- binary(min_length: 1),
              language <- one_of([constant(nil), binary(min_length: 2, max_length: 5)]),
              confidence <-
                one_of([
                  constant(:accepted),
                  constant(:uncertain),
                  constant(:ambiguous),
                  constant(:not_found),
                  constant(:failed),
                  constant(:rejected),
                  constant(:no_value),
                  constant(:unset)
                ]),
              security_level <-
                one_of([
                  constant(nil),
                  constant(:public),
                  constant(:trusted),
                  constant(:admin_owner)
                ])
            ) do
        opts =
          Enum.reject(
            [language: language, confidence: confidence, security_level: security_level],
            fn {_k, v} -> is_nil(v) end
          )

        result = Value.relation(display, authority, opts)

        assert result.value == display
        assert result.authority == authority
        assert result.confidence == confidence
        assert result.security_level == security_level
        if language, do: assert(result.language == language)
      end
    end

    test "raises ArgumentError when :authority in opts (unknown key)" do
      assert_raise ArgumentError, fn ->
        Value.relation("display", "uuid", authority: "other")
      end
    end

    test "invalid confidence in opts is accepted at construction, fails at serialization" do
      value = Value.relation("display", "uuid", confidence: :bogus)

      assert value.confidence == :bogus
      assert_raise FunctionClauseError, fn -> Value.to_map(value) end
    end

    test "raises FunctionClauseError on nil display value" do
      assert_raise FunctionClauseError, fn -> Value.relation(Process.get(:unused, nil), "uuid", []) end
    end

    test "raises FunctionClauseError on empty string display value" do
      assert_raise FunctionClauseError, fn -> Value.relation("", "uuid", []) end
    end

    test "raises FunctionClauseError on nil or empty authority" do
      assert_raise FunctionClauseError, fn -> Value.relation("display", Process.get(:unused, nil), []) end
      assert_raise FunctionClauseError, fn -> Value.relation("display", Process.get(:unused, ""), []) end
    end

    test "raises FunctionClauseError on non-list opts" do
      assert_raise FunctionClauseError, fn ->
        Value.relation("display", "uuid", Process.get(:unused, :not_a_list))
      end
    end

    test "confidence: nil is equivalent to omitting the option" do
      # nil confidence is a deserialization artifact (from_map with "confidence": null)
      assert Value.relation("display", "uuid", confidence: nil).confidence == :uncertain
    end
  end

  describe "wire format conversion" do
    test "to_map/1 with all fields set includes all fields" do
      value = %Value{
        value: "test",
        language: "en",
        authority: "uuid",
        confidence: :accepted,
        place: 0,
        security_level: :public
      }

      result = Value.to_map(value)

      assert result == %{
               "value" => "test",
               "language" => "en",
               "authority" => "uuid",
               "confidence" => 600,
               "place" => 0,
               "securityLevel" => 0
             }
    end

    test "to_map/1 with nil optional fields emits them, except securityLevel" do
      value = %Value{
        value: "test",
        language: nil,
        authority: nil,
        confidence: nil,
        place: nil,
        security_level: nil
      }

      result = Value.to_map(value)

      assert result == %{
               "value" => "test",
               "language" => nil,
               "authority" => nil,
               "confidence" => nil,
               "place" => nil
             }

      refute Map.has_key?(result, "securityLevel")
    end

    test "from_map/1 with securityLevel 1 maps to :trusted" do
      map = %{"value" => "test", "securityLevel" => 1}

      result = Value.from_map(map)

      assert result.security_level == :trusted
    end

    test "to_map/1 with security_level :admin_owner emits securityLevel 2" do
      value = %Value{value: "test", security_level: :admin_owner}

      result = Value.to_map(value)

      assert result["securityLevel"] == 2
    end

    test "from_map/1 with invalid securityLevel raises FunctionClauseError" do
      map = %{"value" => "test", "securityLevel" => 5}

      assert_raise FunctionClauseError, fn ->
        Value.from_map(map)
      end
    end

    test "from_map/1 with known confidence integer maps to atom" do
      map = %{"value" => "test", "confidence" => 500}

      result = Value.from_map(map)

      assert result.confidence == :uncertain
    end

    test "to_map/1 with confidence :accepted emits confidence 600" do
      value = %Value{value: "test", confidence: :accepted}

      result = Value.to_map(value)

      assert result["confidence"] == 600
    end

    test "from_map/1 with unknown confidence integer raises FunctionClauseError" do
      map = %{"value" => "test", "confidence" => 42}

      assert_raise FunctionClauseError, fn ->
        Value.from_map(map)
      end
    end

    test "from_map/1 with missing value key raises FunctionClauseError" do
      map = %{"language" => "en"}

      assert_raise FunctionClauseError, fn ->
        Value.from_map(map)
      end
    end

    test "from_map/1 with non-binary value raises FunctionClauseError" do
      assert_raise FunctionClauseError, fn ->
        Value.from_map(%{"value" => 42})
      end

      assert_raise FunctionClauseError, fn ->
        Value.from_map(%{"value" => nil})
      end

      assert_raise FunctionClauseError, fn ->
        Value.from_map(%{"value" => ["a", "b"]})
      end
    end

    test "from_map/1 with extra unknown keys ignores them" do
      map = %{"value" => "test", "unknownKey" => "ignored"}

      result = Value.from_map(map)

      assert result.value == "test"
    end

    test "from_map/1 with atom-keyed map raises FunctionClauseError (missing string key)" do
      map = %{value: "test"}

      assert_raise FunctionClauseError, fn ->
        Value.from_map(map)
      end
    end
  end

  property "to_map/1 and from_map/1 round-trip" do
    check all(value <- value_generator()) do
      map = Value.to_map(value)
      reconstructed = Value.from_map(map)

      assert reconstructed == value
    end
  end

  property "from_map/1 followed by to_map/1 round-trips (map direction)" do
    check all(
            value_str <- binary(min_length: 1),
            language <- one_of([constant(nil), binary(min_length: 2, max_length: 5)]),
            authority <- one_of([constant(nil), binary()]),
            confidence <-
              one_of([
                constant(nil),
                constant(600),
                constant(500),
                constant(400),
                constant(300),
                constant(200),
                constant(100),
                constant(0),
                constant(-1)
              ]),
            place <- one_of([constant(nil), non_negative_integer()]),
            security_level <- one_of([constant(nil), constant(0), constant(1), constant(2)])
          ) do
      base = %{
        "value" => value_str,
        "language" => language,
        "authority" => authority,
        "confidence" => confidence,
        "place" => place
      }

      input_map =
        if security_level,
          do: Map.put(base, "securityLevel", security_level),
          else: base

      round_tripped =
        input_map
        |> Value.from_map()
        |> Value.to_map()

      assert round_tripped["value"] == value_str
      assert round_tripped["language"] == language
      assert round_tripped["authority"] == authority
      assert round_tripped["place"] == place

      assert round_tripped["confidence"] == confidence

      if security_level do
        assert round_tripped["securityLevel"] == security_level
      else
        refute Map.has_key?(round_tripped, "securityLevel")
      end
    end
  end

  # Private helpers

  defp value_generator do
    base_generator =
      gen all(
            v <- binary(min_length: 0),
            lang <- one_of([constant(nil), binary(min_length: 2, max_length: 5)]),
            auth <- one_of([constant(nil), binary()]),
            conf <-
              one_of([
                constant(nil),
                constant(:accepted),
                constant(:uncertain),
                constant(:ambiguous),
                constant(:not_found),
                constant(:failed),
                constant(:rejected),
                constant(:no_value),
                constant(:unset)
              ]),
            sec <-
              one_of([
                constant(nil),
                constant(:public),
                constant(:trusted),
                constant(:admin_owner)
              ]),
            place <- one_of([constant(nil), non_negative_integer()])
          ) do
        %Value{
          value: v,
          language: lang,
          authority: auth,
          confidence: conf,
          place: place,
          security_level: sec
        }
      end

    one_of([base_generator, constant(Value.placeholder())])
  end
end
