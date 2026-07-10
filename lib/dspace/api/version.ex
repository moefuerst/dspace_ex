defmodule DSpace.API.Version do
  @moduledoc """
  Represents an API compatibility target.

  This module resolves compatibility information from a `DSpace.API` structure and provides
  helpers for discovering API version information from a live DSpace or DSpace-CRIS instance.
  Most users will not need to use this module directly. The functionality is mainly used
  internally (it drives compatibility resolution when executing API operations).

  ## CRIS fork compatibility

  The published [API spec for the CRIS fork](https://github.com/4Science/Rest7Contract) does not
  list any branches or tags prior to the 2023.01.01 release. Unless where known otherwise, this
  release is therefore the assumed baseline for operation compatibility checks.

  That means all versions prior to this release might be flagged as incompatible to execute an
  operation, even though they may actually be compatible with the API. If your application targets
  an older CRIS release and you suspect a false positive:

    * test the operation in question without enabling compatibility checks by not setting
      `cris_version` of the `t:DSpace.API.t/0` when you perform it
    * selectively disable the compatibility check for an operation by modifying its
      `before_step` so that `api_version` and `cris_version` is set to `nil` in the passed
      `t:DSpace.API.t/0`
    * do not enable compatibility checks at all

  If you confirmed a false positive, please open an
  [Issue](https://github.com/moefuerst/dspace_ex/issues)
  """
  @moduledoc since: "0.2.0"

  alias DSpace.API
  alias DSpace.API.Error
  alias DSpace.API.HTTP.Response
  alias DSpace.API.Operation
  alias Elixir.Version, as: ExVersion

  @ep_api "/api"

  @latest "10.0.0"

  @cris_release_map %{
    # DSpace 9.x
    "2025.02.00" => "9.2.0",
    # DSpace 8.x
    "2024.02.04" => "8.2.0",
    "2024.02.03" => "8.2.0",
    "2024.02.02" => "8.2.0",
    "2024.02.01" => "8.1.0",
    "2024.02.00" => "8.0.0",
    # DSpace 7.6.x
    "2023.02.07" => "7.6.3",
    "2023.02.06" => "7.6.2",
    "2023.02.05" => "7.6.1",
    "2023.02.04" => "7.6.1",
    "2023.02.03" => "7.6.1",
    "2023.02.02" => "7.6.1",
    "2023.02.01" => "7.6.1",
    "2023.02.00" => "7.6.1",
    # DSpace 7.5.x
    "2023.01.01" => "7.5.0",
    "2023.01.00" => "7.5.0",
    # DSpace 7.4.x
    "2022.03.02" => "7.4.0",
    "2022.03.01" => "7.4.0",
    "2022.03.00" => "7.4.0",
    # DSpace 7.3.x
    "2022.02.00" => "7.3.0",
    # DSpace 7.2.x
    "2022.01.02" => "7.2.1",
    "2022.01.01" => "7.2.1",
    "2022.01.00" => "7.2.0",
    # DSpace 7.1.x
    "2021.02.02" => "7.1.1",
    "2021.02.01" => "7.1.0",
    # DSpace 7.0.x
    "2021.02.00" => "7.0.0",
    "2021.01.01" => "7.0.0"
  }

  @cris_release_map_parsed Map.new(@cris_release_map, fn {k, v} ->
                             [year, major, minor] = String.split(k, ".")

                             parsed_key =
                               "#{year}.#{String.to_integer(major)}.#{String.to_integer(minor)}"

                             {parsed_key, ExVersion.parse!(v)}
                           end)

  @latest_cris @cris_release_map
               |> Map.keys()
               |> Enum.max()

  # Matches the leading "M.N.P" in strings like "10.1-SNAPSHOT" or "8.0.1 (build 123)".
  @dspace_semver_regex ~r/^(\d+)\.(\d+)(?:\.(\d+))?/

  # Matches the leading "YYYY.M.N" or "YYYY.M.N.P" CRIS release in strings like
  # "2021.01.01-SNAPSHOT".
  @cris_release_regex ~r/^(\d{4})\.(\d{2})\.(\d{2})(?:\.\d{2})?/

  defstruct distribution: :unknown,
            api_version: nil,
            cris_version: nil

  @typedoc """
  Compatibility target for a `DSpace.API` client.

  `api_version` always refers to the base DSpace version, even when the client is configured to
  target the CRIS fork
  """
  @type t :: %__MODULE__{
          distribution: distribution(),
          api_version: ExVersion.t() | nil,
          cris_version: ExVersion.t() | nil
        }

  @typedoc """
  Target distribution.
  """
  @type distribution :: :dspace | :cris | :unknown

  # Public API

  @doc """
  Fetches version information from the API.

  Executing this operation returns a `t:t/0` structure.

  ## Example

      client =
        [endpoint: "https://example.com/server"]
        |> DSpace.API.new()

      {:ok, %DSpace.API.Version{} = version} =
        DSpace.API.Version.fetch()
        |> DSpace.API.request(client)
  """
  @spec fetch() :: Operation.t()
  def fetch do
    %Operation.JSON{path: @ep_api, transformer: &from_response/1}
  end

  @doc """
  Resolves compatibility information from a `DSpace.API` structure.

  The configured values are normalized. When both `:api_version` and `:cris_version` are
  configured, `:cris_version` determines the distribution. If the base DSpace version is missing
  or cannot be parsed, an internal CRIS release mapping is used as a fallback.
  """
  @spec resolve(API.t()) :: t()
  def resolve(%API{api_version: api_version, cris_version: cris_version}) do
    case {parse_dspace_version(api_version), parse_cris_version(cris_version)} do
      {api, %ExVersion{} = cris} ->
        %__MODULE__{
          distribution: :cris,
          api_version: api || lookup_cris_version(cris),
          cris_version: cris
        }

      {%ExVersion{} = api, nil} ->
        %__MODULE__{
          distribution: :dspace,
          api_version: api
        }

      _ ->
        %__MODULE__{}
    end
  end

  @doc """
  Parses a DSpace version string into a `t:Elixir.Version.t/0`.
  """
  @spec parse_dspace_version(dspace_version_string :: binary()) :: ExVersion.t() | nil
  def parse_dspace_version("DSpace " <> version), do: parse_dspace_semver(version)
  def parse_dspace_version("Version " <> version), do: parse_dspace_semver(version)
  def parse_dspace_version(version) when is_binary(version), do: parse_dspace_semver(version)
  def parse_dspace_version(_version), do: nil

  @doc """
  Parses a CRIS release string into a `t:Elixir.Version.t/0`.
  """
  @spec parse_cris_version(cris_release_string :: binary()) :: ExVersion.t() | nil
  def parse_cris_version("dspace-cris-" <> version), do: parse_cris_release(version)
  def parse_cris_version("cris-" <> version), do: parse_cris_release(version)
  def parse_cris_version(version) when is_binary(version), do: parse_cris_release(version)
  def parse_cris_version(_version), do: nil

  # API for internal use

  @doc false
  # Checks whether the resolved version target is compatible with a version requirements map.
  @spec check_compatibility(t(), %{(:any | :dspace | :cris) => binary()}) ::
          :ok
          | {:error, {:unsupported_distribution, distribution()}}
          | {:error, {:unsupported_version, binary()}}
          | {:error, {:parse_error, binary()}}
  def check_compatibility(%__MODULE__{distribution: :unknown}, _supported_versions) do
    :ok
  end

  def check_compatibility(%__MODULE__{distribution: distribution} = version, supported_versions)
      when is_map(supported_versions) do
    case resolve_requirement(supported_versions, distribution) do
      {requirement, matched_key} ->
        version_struct = version_for_key(version, matched_key)
        check_requirement(version_struct, requirement)

      nil ->
        {:error, {:unsupported_distribution, distribution}}
    end
  end

  @doc false
  # Checks whether the version in the given structure matches the given requirement.
  @spec version_matches?(target, requirement) :: boolean()
        when target: ExVersion.t() | API.t() | t(),
             requirement: binary() | %{(:any | :dspace | :cris) => binary()}
  def version_matches?(%ExVersion{} = target, spec) when is_binary(spec) do
    case ExVersion.parse_requirement(spec) do
      {:ok, requirement} -> ExVersion.match?(target, requirement)
      :error -> false
    end
  end

  def version_matches?(%__MODULE__{distribution: :unknown, api_version: nil, cris_version: nil}, _spec) do
    true
  end

  def version_matches?(%__MODULE__{distribution: dist} = target, spec) when is_map(spec) do
    Enum.all?(spec, fn
      {key, value} when key in [:dspace, :cris, :any] and is_binary(value) ->
        distribution_matches?(dist, key) and
          version_matches?(version_for_key(target, key), value)

      _ ->
        false
    end)
  end

  def version_matches?(%API{} = target, spec) do
    target
    |> resolve()
    |> version_matches?(spec)
  end

  def version_matches?(%__MODULE__{distribution: dist, api_version: %ExVersion{} = target}, spec)
      when dist in [:dspace, :cris] and is_binary(spec) do
    version_matches?(target, spec)
  end

  def version_matches?(%__MODULE__{distribution: :cris, cris_version: %ExVersion{} = target}, spec)
      when is_binary(spec) do
    version_matches?(target, spec)
  end

  def version_matches?(%__MODULE__{api_version: %ExVersion{} = target}, spec) when is_binary(spec) do
    version_matches?(target, spec)
  end

  def version_matches?(%__MODULE__{cris_version: %ExVersion{} = target}, spec) when is_binary(spec) do
    version_matches?(target, spec)
  end

  def version_matches?(_target, _spec), do: false

  @doc false
  @spec latest() :: binary()
  def latest, do: @latest

  @doc false
  @spec latest_cris() :: binary()
  def latest_cris, do: @latest_cris

  # Private helpers

  @spec from_response(Response.t()) :: t() | Error.t()
  defp from_response(%Response{body: body} = response) do
    case from_body(body) do
      {:ok, version} -> version
      {:error, message} -> Error.response_validation_error(response, message)
    end
  end

  defp from_body(%{} = body) do
    case resolve(%API{api_version: body["dspaceVersion"], cris_version: body["crisVersion"]}) do
      %__MODULE__{distribution: :unknown} ->
        {:error, "API response does not contain a parseable dspaceVersion or crisVersion."}

      version ->
        {:ok, version}
    end
  end

  defp from_body(_body) do
    {:error, "API response does not contain a parseable version payload."}
  end

  defp parse_dspace_semver(string) do
    # Optional patch segment. Trailing content is ignored.
    case Regex.run(@dspace_semver_regex, string, capture: :all_but_first) do
      [major, minor] -> ExVersion.parse!("#{major}.#{minor}.0")
      [major, minor, patch] -> ExVersion.parse!("#{major}.#{minor}.#{patch}")
      _ -> nil
    end
  end

  defp parse_cris_release(string) do
    # Optional patch segment intentionally dropped. Treat year prefix as major, major as minor,
    # patch as minor. Strip leading zeros so Elixir's Version module accepts the CRIS format.
    case Regex.run(@cris_release_regex, string, capture: :all_but_first) do
      [year, major, minor] ->
        ExVersion.parse!("#{year}.#{String.to_integer(major)}.#{String.to_integer(minor)}")

      _ ->
        nil
    end
  end

  defp lookup_cris_version(%ExVersion{major: year, minor: major, patch: minor}) do
    Map.get(@cris_release_map_parsed, "#{year}.#{major}.#{minor}")
  end

  defp resolve_requirement(versions, dist) when is_map_key(versions, dist), do: {versions[dist], dist}
  defp resolve_requirement(%{any: req}, _dist), do: {req, :any}
  defp resolve_requirement(_versions, _dist), do: nil

  defp version_for_key(%{cris_version: cris_version}, :cris), do: cris_version
  defp version_for_key(%{api_version: api_version}, _key), do: api_version

  defp distribution_matches?(_dist, :any), do: true
  defp distribution_matches?(:unknown, _key), do: true
  defp distribution_matches?(dist, key), do: dist == key

  defp check_requirement(nil, _requirement), do: :ok

  defp check_requirement(%ExVersion{} = version, requirement) do
    case ExVersion.parse_requirement(requirement) do
      {:ok, req} ->
        if ExVersion.match?(version, req) do
          :ok
        else
          {:error, {:unsupported_version, ExVersion.to_string(version)}}
        end

      :error ->
        {:error, {:parse_error, requirement}}
    end
  end
end
