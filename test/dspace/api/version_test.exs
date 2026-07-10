defmodule DSpace.API.VersionTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias DSpace.API
  alias DSpace.API.Error
  alias DSpace.API.Version
  alias Elixir.Version, as: ExVersion

  describe "fetch/0" do
    setup do
      api = %API{endpoint: "https://example.com/server", http_impl: {TestHelper.HTTP, []}}

      {:ok, api: api}
    end

    test "fetches and parses version information", %{api: api} do
      {:ok, result} =
        API.request(Version.fetch(), api,
          test_return_body: %{
            "dspaceVersion" => "DSpace 10.1-SNAPSHOT",
            "crisVersion" => "cris-2025.02.00"
          }
        )

      assert %Version{
               distribution: :cris,
               api_version: %ExVersion{major: 10, minor: 1, patch: 0},
               cris_version: %ExVersion{major: 2025, minor: 2, patch: 0}
             } = result
    end

    test "returns a validation error when the payload contains no parseable version values",
         %{api: api} do
      {:error, result} =
        API.request(Version.fetch(), api, test_return_body: %{"test" => "data"})

      assert %Error{type: :api_unexpected_payload} = result
    end

    test "response transform builds a DSpace target from dspaceVersion only", %{api: api} do
      {:ok, result} =
        API.request(Version.fetch(), api, test_return_body: %{"dspaceVersion" => "DSpace 10.1-SNAPSHOT"})

      assert %Version{
               distribution: :dspace,
               api_version: %ExVersion{major: 10, minor: 1, patch: 0},
               cris_version: nil
             } = result
    end

    test "response transform builds a CRIS target from crisVersion only, mapping the DSpace base version",
         %{api: api} do
      {:ok, result} =
        API.request(Version.fetch(), api, test_return_body: %{"crisVersion" => "cris-2023.02.02"})

      assert %Version{
               distribution: :cris,
               api_version: %ExVersion{major: 7, minor: 6, patch: 1},
               cris_version: %ExVersion{major: 2023, minor: 2, patch: 2}
             } = result
    end

    test "response transform builds a CRIS target from both version fields", %{api: api} do
      {:ok, result} =
        API.request(Version.fetch(), api,
          test_return_body: %{
            "dspaceVersion" => "Version 9.0.1 (build 123)",
            "crisVersion" => "cris-2023.02.02"
          }
        )

      assert %Version{
               distribution: :cris,
               api_version: %ExVersion{major: 9, minor: 0, patch: 1},
               cris_version: %ExVersion{major: 2023, minor: 2, patch: 2}
             } = result
    end

    test "response transform maps the DSpace base version if the field can't be parsed",
         %{api: api} do
      {:ok, result} =
        API.request(Version.fetch(), api,
          test_return_body: %{
            "dspaceVersion" => "snapshot",
            "crisVersion" => "2023.02.02"
          }
        )

      assert %Version{
               distribution: :cris,
               api_version: %ExVersion{major: 7, minor: 6, patch: 1},
               cris_version: %ExVersion{major: 2023, minor: 2, patch: 2}
             } = result
    end

    test "response transform returns an error when neither version field can be parsed",
         %{api: api} do
      {:error, result} =
        API.request(Version.fetch(), api,
          test_return_body: %{
            "dspaceVersion" => "snapshot",
            "crisVersion" => "latest"
          }
        )

      assert %Error{type: :api_unexpected_payload} = result
    end
  end

  describe "resolve/1" do
    test "parses formatted api_version values from the client" do
      client = %API{api_version: "Version 9.0.1 (build 123)", cris_version: nil}

      result = Version.resolve(client)

      assert %Version{
               distribution: :dspace,
               api_version: %ExVersion{major: 9, minor: 0, patch: 1},
               cris_version: nil
             } = result
    end

    test "resolves a client with only api_version as vanilla DSpace" do
      client = %API{api_version: "9.2.0", cris_version: nil}

      result = Version.resolve(client)

      assert %Version{
               distribution: :dspace,
               api_version: %ExVersion{major: 9, minor: 2, patch: 0},
               cris_version: nil
             } = result
    end

    test "resolves a client with only cris_version as CRIS and maps the base DSpace version" do
      client = %API{api_version: nil, cris_version: "2025.02.00"}

      result = Version.resolve(client)

      assert %Version{
               distribution: :cris,
               api_version: %ExVersion{major: 9, minor: 2, patch: 0},
               cris_version: %ExVersion{major: 2025, minor: 2, patch: 0}
             } = result
    end

    test "normalizes a cris_version with the cris- prefix" do
      client = %API{api_version: nil, cris_version: "cris-2025.02.00"}

      result = Version.resolve(client)

      assert %Version{
               distribution: :cris,
               api_version: %ExVersion{major: 9, minor: 2, patch: 0},
               cris_version: %ExVersion{major: 2025, minor: 2, patch: 0}
             } = result
    end

    test "prefers the explicit api_version when both version fields are set" do
      client = %API{api_version: "Version 9.0.1 (build 123)", cris_version: "cris-2025.02.00"}

      result = Version.resolve(client)

      assert %Version{
               distribution: :cris,
               api_version: %ExVersion{major: 9, minor: 0, patch: 1},
               cris_version: %ExVersion{major: 2025, minor: 2, patch: 0}
             } = result
    end

    test "falls back to api_version semantics when the CRIS release is unknown" do
      client = %API{api_version: "9.2.0", cris_version: "cris-2099.01.00"}

      result = Version.resolve(client)

      assert %Version{
               distribution: :cris,
               api_version: %ExVersion{major: 9, minor: 2, patch: 0},
               cris_version: %ExVersion{major: 2099, minor: 1, patch: 0}
             } = result
    end

    test "returns an unknown target when neither version field is configured" do
      client = %API{api_version: nil, cris_version: nil}

      result = Version.resolve(client)

      assert %Version{
               distribution: :unknown,
               api_version: nil,
               cris_version: nil
             } = result
    end
  end

  describe "parse_dspace_version/1" do
    test "extracts and normalizes a version from formatted DSpace strings" do
      assert Version.parse_dspace_version("DSpace 10.1-SNAPSHOT") == ExVersion.parse!("10.1.0")
      assert Version.parse_dspace_version("Version 9.0.1 (build 123)") == ExVersion.parse!("9.0.1")
      assert Version.parse_dspace_version("9.2.0") == ExVersion.parse!("9.2.0")
    end

    property "parses bare and prefixed M.N.P strings to the same Version.t()" do
      check all(
              major <- non_negative_integer(),
              minor <- non_negative_integer(),
              patch <- non_negative_integer()
            ) do
        expected = ExVersion.parse!("#{major}.#{minor}.#{patch}")
        bare = "#{major}.#{minor}.#{patch}"

        assert Version.parse_dspace_version(bare) == expected
        assert Version.parse_dspace_version("DSpace " <> bare) == expected
        assert Version.parse_dspace_version("Version " <> bare) == expected
      end
    end

    property "returns nil on inputs that cannot match M.N at the start" do
      # build strings that are structurally guaranteed not to match ^(\d+)\.(\d+):
      malformed_gen =
        one_of([
          map(
            {string(:ascii, min_length: 1), string(:printable, min_length: 0)},
            fn {a, rest} -> "a" <> a <> rest end
          ),
          map(non_negative_integer(), &to_string/1),
          map(
            {non_negative_integer(), non_negative_integer()},
            fn {a, b} -> ".#{a}.#{b}" end
          )
        ])

      check all(input <- malformed_gen) do
        assert is_nil(Version.parse_dspace_version(input))
      end
    end

    property "normalizes M.N to M.N.0, ignoring any trailing non-numeric suffix" do
      # generator samples the kinds of real-world suffixes that appear in Maven version strings
      suffix_gen =
        one_of([
          constant(""),
          # pre-release labels: -SNAPSHOT, -RC1, -alpha2
          map(string(:alphanumeric, min_length: 1), &("-" <> &1)),
          # build metadata: +build.7, +20240101
          map(string(:alphanumeric, min_length: 1), &("+" <> &1)),
          # parenthetical build info: " (build 123)"
          map(positive_integer(), &(" (build " <> to_string(&1) <> ")")),
          # bare whitespace-separated labels: " SNAPSHOT", " RC1"
          map(string(:alphanumeric, min_length: 1), &(" " <> &1)),
          # mixed punctuation seen in the wild: " SNAPSHOT-1", "-rc.2"
          map(
            {string(:alphanumeric, min_length: 1), string(:alphanumeric, min_length: 1)},
            fn {a, b} -> "-" <> a <> "." <> b end
          )
        ])

      check all(
              major <- positive_integer(),
              minor <- non_negative_integer(),
              suffix <- suffix_gen
            ) do
        assert Version.parse_dspace_version("DSpace #{major}.#{minor}#{suffix}") ==
                 ExVersion.parse!("#{major}.#{minor}.0")
      end
    end

    test "returns nil for empty string" do
      assert is_nil(Version.parse_dspace_version(""))
    end
  end

  describe "parse_cris_version/1" do
    test "extracts and normalizes a version from formatted CRIS release string" do
      assert Version.parse_cris_version("cris-2023.02.02") == ExVersion.parse!("2023.2.2")
      assert Version.parse_cris_version("dspace-cris-2023.02.02") == ExVersion.parse!("2023.2.2")
      assert Version.parse_cris_version("cris-2023.02.02-SNAPSHOT") == ExVersion.parse!("2023.2.2")
      assert Version.parse_cris_version("2023.02.02") == ExVersion.parse!("2023.2.2")
    end

    test "strips P component from YYYY.M.N.P CRIS release versions" do
      assert Version.parse_cris_version("2024.02.04.01") == ExVersion.parse!("2024.2.4")
      assert Version.parse_cris_version("cris-2024.02.04.01") == ExVersion.parse!("2024.2.4")
      assert Version.parse_cris_version("2023.02.07.03") == ExVersion.parse!("2023.2.7")
    end

    property "parses bare and prefixed version strings to the same Version.t()" do
      check all(
              year <- integer(2021..2030),
              major <- integer(0..99),
              minor <- integer(0..99)
            ) do
        m = String.pad_leading("#{major}", 2, "0")
        n = String.pad_leading("#{minor}", 2, "0")
        version = "#{year}.#{m}.#{n}"
        expected = ExVersion.parse!("#{year}.#{major}.#{minor}")

        assert Version.parse_cris_version(version) == expected
        assert Version.parse_cris_version("cris-" <> version) == expected
        assert Version.parse_cris_version("dspace-cris-" <> version) == expected
      end
    end

    property "returns nil for inputs that cannot match YYYY.MM.NN" do
      malformed_cris_gen =
        one_of([
          # wrong year width: 1, 2, or 3 digits instead of exactly 4
          map(
            {integer(1..999), integer(0..99), integer(0..99)},
            fn {y, major, minor} ->
              m = String.pad_leading("#{major}", 2, "0")
              n = String.pad_leading("#{minor}", 2, "0")
              "#{y}.#{m}.#{n}"
            end
          ),
          # wrong M/N width: only 1 digit each instead of exactly 2
          map(
            {integer(2021..2030), integer(0..9), integer(0..9)},
            fn {y, major, minor} -> "#{y}.#{major}.#{minor}" end
          ),
          # non-digit segment: "2023.ab.01"
          map(
            {integer(2021..2030), string(:ascii, min_length: 1), integer(0..99)},
            fn {y, seg, minor} ->
              n = String.pad_leading("#{minor}", 2, "0")
              "#{y}." <> ("a" <> seg) <> ".#{n}"
            end
          ),
          # missing components: just "2023" or "2023.01"
          map(integer(2021..2030), &to_string/1),
          map(
            {integer(2021..2030), integer(0..99)},
            fn {y, major} -> "#{y}.#{String.pad_leading("#{major}", 2, "0")}" end
          )
        ])

      check all(input <- malformed_cris_gen) do
        assert is_nil(Version.parse_cris_version(input))
        assert is_nil(Version.parse_cris_version("cris-" <> input))
        assert is_nil(Version.parse_cris_version("dspace-cris-" <> input))
      end
    end

    property "normalizes YYYY.M.N.P to YYYY.M.N, dropping the patch segment" do
      check all(
              year <- integer(2021..2030),
              major <- integer(0..99),
              minor <- integer(0..99),
              patch <- integer(0..99)
            ) do
        m = String.pad_leading("#{major}", 2, "0")
        n = String.pad_leading("#{minor}", 2, "0")
        p = String.pad_leading("#{patch}", 2, "0")
        expected = ExVersion.parse!("#{year}.#{major}.#{minor}")

        assert Version.parse_cris_version("#{year}.#{m}.#{n}.#{p}") == expected
      end
    end

    test "returns nil for empty string" do
      assert is_nil(Version.parse_cris_version(""))
    end
  end

  describe "check_compatibility/2" do
    test "checks cris_version when the :cris key matches a CRIS distribution" do
      version = %Version{distribution: :cris, api_version: v("7.5.0"), cris_version: v("2023.1.0")}

      assert :ok = Version.check_compatibility(version, %{cris: ">= 2023.1.0"})
    end

    test "checks api_version when the :dspace key matches a DSpace distribution" do
      version = %Version{distribution: :dspace, api_version: v("10.0.0")}

      assert :ok = Version.check_compatibility(version, %{dspace: ">= 10.0.0"})
    end

    test "checks api_version when the :any key is used" do
      dspace = %Version{distribution: :dspace, api_version: v("9.0.0")}
      cris = %Version{distribution: :cris, api_version: v("7.5.0"), cris_version: v("2023.1.0")}

      assert :ok = Version.check_compatibility(dspace, %{any: ">= 7.0.0"})
      assert :ok = Version.check_compatibility(cris, %{any: ">= 7.0.0"})
    end

    test "supports different version thresholds per distribution" do
      supported = %{dspace: ">= 10.0.0", cris: ">= 2023.1.0"}

      # CRIS 2023.1.0 maps to DSpace 7.5.0 which would fail a flat >= 10.0.0 check,
      # but passes because the CRIS requirement checks cris_version
      cris = %Version{distribution: :cris, api_version: v("7.5.0"), cris_version: v("2023.1.0")}
      assert :ok = Version.check_compatibility(cris, supported)

      # DSpace 9.0 doesn't meet >= 10.0.0
      dspace_9 = %Version{distribution: :dspace, api_version: v("9.0.0")}
      assert {:error, {:unsupported_version, _}} = Version.check_compatibility(dspace_9, supported)

      # DSpace 10.0 meets >= 10.0.0
      dspace_10 = %Version{distribution: :dspace, api_version: v("10.0.0")}
      assert :ok = Version.check_compatibility(dspace_10, supported)
    end

    test "uses a specific distribution key over :any" do
      supported = %{any: ">= 7.0.0", cris: ">= 2024.2.0"}

      # CRIS 2023.1.0 matches :any >= 7.0.0 via api_version, but the :cris key
      # should take precedence and check cris_version against >= 2024.02.00
      old_cris = %Version{distribution: :cris, api_version: v("7.5.0"), cris_version: v("2023.1.0")}
      assert {:error, {:unsupported_version, "2023.1.0"}} = Version.check_compatibility(old_cris, supported)

      new_cris = %Version{distribution: :cris, api_version: v("8.0.0"), cris_version: v("2024.2.0")}
      assert :ok = Version.check_compatibility(new_cris, supported)
    end

    test "falls back to :any when specific distribution key is absent" do
      supported = %{any: ">= 7.0.0", cris: ">= 2023.1.0"}

      # :dspace not in map, falls back to :any, checks api_version
      dspace = %Version{distribution: :dspace, api_version: v("9.0.0")}

      assert :ok = Version.check_compatibility(dspace, supported)
    end

    test "returns unsupported_distribution when distribution is not in map and no :any fallback" do
      cris_only = %{cris: ">= 2023.01.00"}

      dspace = %Version{distribution: :dspace, api_version: v("10.0.0")}
      assert {:error, {:unsupported_distribution, :dspace}} = Version.check_compatibility(dspace, cris_only)
    end

    test "returns unsupported_version with the checked version string on mismatch" do
      version = %Version{distribution: :dspace, api_version: v("9.0.0")}

      assert {:error, {:unsupported_version, "9.0.0"}} =
               Version.check_compatibility(version, %{dspace: ">= 10.0.0"})
    end

    test "returns unsupported_version with the cris_version string on CRIS mismatch" do
      version = %Version{distribution: :cris, api_version: v("7.5.0"), cris_version: v("2023.1.0")}

      assert {:error, {:unsupported_version, "2023.1.0"}} =
               Version.check_compatibility(version, %{cris: ">= 2024.2.0"})
    end

    test "optimistically allows :unknown distribution" do
      unknown = %Version{distribution: :unknown, api_version: nil, cris_version: nil}

      assert :ok = Version.check_compatibility(unknown, %{dspace: ">= 10.0.0"})
      assert :ok = Version.check_compatibility(unknown, %{cris: ">= 2023.1.0"})
      assert :ok = Version.check_compatibility(unknown, %{any: ">= 7.0.0"})
    end

    test "optimistically allows when the relevant version is nil" do
      # these would be unusual edge cases
      dspace_no_version = %Version{distribution: :dspace, api_version: nil}
      cris_no_version = %Version{distribution: :cris, api_version: v("7.5.0"), cris_version: nil}

      assert :ok = Version.check_compatibility(dspace_no_version, %{dspace: ">= 10.0.0"})
      assert :ok = Version.check_compatibility(cris_no_version, %{cris: ">= 2023.1.0"})
    end

    test "returns parse_error with the requirement string for an unparseable requirement" do
      version = %Version{distribution: :cris, api_version: v("7.5.0"), cris_version: v("2023.1.0")}

      assert {:error, {:parse_error, ">= 2023.01.00"}} =
               Version.check_compatibility(version, %{cris: ">= 2023.01.00"})
    end
  end

  describe "version_matches?/2" do
    test "accepts an API struct target with version string value" do
      client = %API{api_version: "10.1.0"}

      assert Version.version_matches?(client, ">= 10.1.0")
    end

    test "accepts a Version struct target with Elixir.Version struct value" do
      version = %Version{api_version: %ExVersion{major: 10, minor: 1, patch: 0}}

      assert Version.version_matches?(version, ">= 10.1.0")
    end

    test "accepts an Elixir.Version struct target" do
      version = %ExVersion{major: 10, minor: 1, patch: 0}

      assert Version.version_matches?(version, ">= 10.1.0")
    end

    test "returns false on invalid target shapes instead of raising" do
      version = [major: 10, minor: 1, patch: 0]

      refute Version.version_matches?(version, ">= 10.1.0")
    end

    test "returns true for unparseable configured versions" do
      client = %API{api_version: "snapshot", cris_version: nil}

      assert Version.version_matches?(client, ">= 9.0.0")
    end

    test "returns true when no normalized version is available" do
      client = %API{api_version: nil, cris_version: nil}

      assert Version.version_matches?(client, ">= 9.0.0")
    end

    test "returns false for invalid requirements" do
      client = %API{api_version: "9.2.0", cris_version: nil}

      refute Version.version_matches?(client, "not-a-version-spec")
    end

    test "matches against the mapped base DSpace version when it's not given" do
      client = %API{api_version: nil, cris_version: "cris-2024.02.01"}

      # matches 8.1.0, which is the base version of 2024.2.1
      assert Version.version_matches?(client, ">= 8.0.0 and < 9.0.0")

      # would fail if matching against cris_version (2024 > 100)
      refute Version.version_matches?(client, ">= 100.0.0")
    end

    test "matches a :dspace target against an %{any: req}" do
      dspace = %Version{distribution: :dspace, api_version: v("10.0.0")}

      assert Version.version_matches?(dspace, %{any: ">= 9.0.0"})
      refute Version.version_matches?(dspace, %{any: ">= 11.0.0"})
    end

    test "matches a :cris target against an %{any: req} based on api_version" do
      cris = %Version{distribution: :cris, api_version: v("8.1.0"), cris_version: v("2024.2.1")}

      assert Version.version_matches?(cris, %{any: ">= 8.0.0"})
      refute Version.version_matches?(cris, %{any: ">= 9.0.0"})
    end

    test "matches a %{cris: req} against cris_version, not api_version" do
      # api_version would satisfy >= 8.0.0; cris_version would not satisfy >= 2025.0.0
      cris = %Version{distribution: :cris, api_version: v("8.1.0"), cris_version: v("2024.2.1")}

      assert Version.version_matches?(cris, %{cris: ">= 2024.0.0"})
      refute Version.version_matches?(cris, %{cris: ">= 2025.0.0"})
    end

    test "matches multiple requirement keys using AND semantics" do
      cris = %Version{distribution: :cris, api_version: v("8.1.0"), cris_version: v("2024.2.1")}

      assert Version.version_matches?(cris, %{any: ">= 8.0.0", cris: ">= 2024.0.0"})

      # api_version passes, cris_version fails: whole spec must be false
      refute Version.version_matches?(cris, %{any: ">= 8.0.0", cris: ">= 2025.0.0"})
    end

    test "does not match a :dspace target against a %{cris: req}" do
      dspace = %Version{distribution: :dspace, api_version: v("10.0.0")}

      refute Version.version_matches?(dspace, %{cris: ">= 7.0.0"})
    end

    test "does not match a :cris target against a %{dspace: req}" do
      cris = %Version{distribution: :cris, api_version: v("8.1.0"), cris_version: v("2024.2.1")}

      refute Version.version_matches?(cris, %{dspace: ">= 8.0.0"})
    end

    test "does not match an unrecognised requirement key" do
      dspace = %Version{distribution: :dspace, api_version: v("10.0.0")}

      refute Version.version_matches?(dspace, %{foo: ">= 1.0.0"})
    end

    test "returns true for an :unknown distribution, matching any spec form" do
      unknown = %Version{distribution: :unknown, api_version: nil, cris_version: nil}

      assert Version.version_matches?(unknown, %{any: ">= 9.0.0"})
      assert Version.version_matches?(unknown, %{dspace: ">= 10.0.0"})
      assert Version.version_matches?(unknown, %{cris: ">= 2024.0.0"})
      assert Version.version_matches?(unknown, %{any: ">= 9.0.0", cris: ">= 2024.0.0"})
    end
  end

  describe "latest release helpers" do
    test "latest/0 resolves to a :dspace target with a non-nil api_version" do
      assert %Version{distribution: :dspace, api_version: %ExVersion{}} =
               Version.resolve(%API{api_version: Version.latest()})
    end

    test "latest_cris/0 resolves to a :cris target with non-nil api_version and cris_version" do
      # verifies that latest_cris/0 is present in the CRIS-to-DSpace release map:
      # a release that is parseable but unmapped would produce api_version: nil
      assert %Version{distribution: :cris, api_version: %ExVersion{}, cris_version: %ExVersion{}} =
               Version.resolve(%API{cris_version: Version.latest_cris()})
    end
  end

  # Private helpers

  defp v(string), do: ExVersion.parse!(string)
end
