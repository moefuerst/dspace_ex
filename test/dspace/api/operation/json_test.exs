defmodule DSpace.API.Operation.JSONTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias DSpace.API
  alias DSpace.API.HTTP.Response
  alias DSpace.API.Operation
  alias DSpace.API.Operation.Error
  alias DSpace.API.Operation.JSON, as: JSONOp
  alias DSpace.API.Version

  setup do
    client =
      %API{
        endpoint: "https://example.com/server",
        http_impl: {TestHelper.HTTP, []},
        csrf_token: "test-csrf-token",
        access_token: "test-access-token"
      }

    {:ok, client: client}
  end

  describe "put_lang/2" do
    test "sets allLanguages projection when lang: :all" do
      operation =
        [path: "/api/test"]
        |> JSONOp.new()
        |> JSONOp.put_lang(lang: :all)

      assert Keyword.get(operation.params, :projection) == "allLanguages"
      refute Map.has_key?(operation.headers, :accept_language)
    end

    test "sets Accept-Language header with quality values for multiple languages" do
      operation =
        [path: "/api/test"]
        |> JSONOp.new()
        |> JSONOp.put_lang(lang: [:en, :de, :fr])

      %{:accept_language => value} = operation.headers

      assert value == ["en,de;q=0.9,fr;q=0.8"]
      refute Keyword.has_key?(operation.params, :projection)
    end

    test "clamps q to 0.1 for long language lists" do
      operation =
        [path: "/api/test"]
        |> JSONOp.new()
        |> JSONOp.put_lang(lang: [:l1, :l2, :l3, :l4, :l5, :l6, :l7, :l8, :l9, :l10, :l11, :l12])

      %{:accept_language => value} = operation.headers

      expected =
        "l1,l2;q=0.9,l3;q=0.8,l4;q=0.7,l5;q=0.6,l6;q=0.5,l7;q=0.4,l8;q=0.3,l9;q=0.2,l10;" <>
          "q=0.1,l11;q=0.1,l12;q=0.1"

      assert value == [expected]
      refute Keyword.has_key?(operation.params, :projection)
    end

    test "sets Accept-Language header for a single language" do
      operation =
        [path: "/api/test"]
        |> JSONOp.new()
        |> JSONOp.put_lang(lang: :en)

      %{:accept_language => value} = operation.headers

      assert value == ["en"]
      refute Keyword.has_key?(operation.params, :projection)
    end

    test "sets Accept-Language header with binary input" do
      operation =
        [path: "/api/test"]
        |> JSONOp.new()
        |> JSONOp.put_lang(lang: "fr-CH,fr;q=0.9,en;q=0.8,de;q=0.7")

      %{:accept_language => value} = operation.headers

      assert value == ["fr-CH,fr;q=0.9,en;q=0.8,de;q=0.7"]
      refute Keyword.has_key?(operation.params, :projection)
    end

    test "passes Accept-Language header" do
      operation =
        [path: "/api/test"]
        |> JSONOp.new()
        |> JSONOp.put_lang(lang: %{accept_language: ["fr-CH"]})

      %{:accept_language => value} = operation.headers

      assert value == ["fr-CH"]
      refute Keyword.has_key?(operation.params, :projection)
    end
  end

  describe "CSRF handling" do
    test "does not require CSRF token for GET operations", %{client: client} do
      client = %{client | csrf_token: nil}
      operation = JSONOp.new(path: "/api/test")

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:method] == :get
      refute Map.has_key?(options[:headers], :x_xsrf_token)
    end

    test "does not require CSRF token for HEAD operations", %{client: client} do
      client = %{client | csrf_token: nil}
      operation = JSONOp.new(path: "/api/test", http_method: :head)

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:method] == :head
      refute Map.has_key?(options[:headers], :x_xsrf_token)
    end

    test "requires CSRF token for POST operations", %{client: client} do
      client = %{client | csrf_token: nil}
      operation = JSONOp.new(path: "/api/test", http_method: :post, data: %{})

      result = Operation.perform(operation, client, [])

      assert {:error, %Error{}} = result
    end

    test "requires CSRF token for PUT operations", %{client: client} do
      client = %{client | csrf_token: nil}
      operation = JSONOp.new(path: "/api/test", http_method: :put, data: %{})

      result = Operation.perform(operation, client, [])

      assert {:error, %Error{}} = result
    end

    test "requires CSRF token for PATCH operations", %{client: client} do
      client = %{client | csrf_token: nil}
      operation = JSONOp.new(path: "/api/test", http_method: :patch, data: %{})

      result = Operation.perform(operation, client, [])

      assert {:error, %Error{}} = result
    end

    test "requires CSRF token for DELETE operations", %{client: client} do
      client = %{client | csrf_token: nil}
      operation = JSONOp.new(path: "/api/test", http_method: :delete)

      result = Operation.perform(operation, client, [])

      assert {:error, %Error{}} = result
    end

    test "includes CSRF token for mutating operations when present", %{client: client} do
      operation = JSONOp.new(path: "/api/test", http_method: :post, data: %{})

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:headers][:x_xsrf_token] == ["test-csrf-token"]
    end

    test "includes CSRF token for GET when available", %{client: client} do
      operation = JSONOp.new(path: "/api/test")

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:headers][:x_xsrf_token] == ["test-csrf-token"]
    end
  end

  describe "HTTP support" do
    test "includes query parameters in request", %{client: client} do
      operation = JSONOp.new(path: "/api/test", params: [page: 1, size: 20, sort: "name,asc"])

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:params] == [page: 1, size: 20, sort: "name,asc"]
    end

    test "includes headers in request", %{client: client} do
      operation = JSONOp.new(path: "/api/test", headers: %{:x_custom_header => ["custom-value"]})

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:headers][:x_custom_header] == ["custom-value"]
    end
  end

  describe "content type handling" do
    test "handles :json content_type with default content-type", %{client: client} do
      operation =
        JSONOp.new(
          path: "/api/test",
          http_method: :post,
          content_type: :json,
          data: %{"key" => "value"}
        )

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:json] == %{"key" => "value"}
    end

    test "handles :form content_type with form encoding", %{client: client} do
      operation =
        JSONOp.new(
          path: "/api/auth",
          http_method: :post,
          content_type: :form,
          data: %{"username" => "test", "password" => "secret"}
        )

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:form] == %{"username" => "test", "password" => "secret"}
    end

    test "handles :multipart content_type with multipart encoding", %{client: client} do
      operation =
        JSONOp.new(
          path: "/api/upload",
          http_method: :post,
          content_type: :multipart,
          data: %{"file" => "content", "metadata" => "info"}
        )

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:form_multipart] == %{"file" => "content", "metadata" => "info"}
    end

    test "handles :uri_list content_type with uri list encoding", %{client: client} do
      operation =
        JSONOp.new(
          path: "/api/batch",
          http_method: :post,
          content_type: :uri_list,
          data: ["https://example.com/1", "https://example.com/2"]
        )

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:body] == "https://example.com/1\nhttps://example.com/2"
      assert options[:headers][:content_type] == ["text/uri-list"]
    end

    test "does not include body options when data is nil", %{client: client} do
      operation = JSONOp.new(path: "/api/test")

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      refute Keyword.has_key?(options, :json)
      refute Keyword.has_key?(options, :form)
      refute Keyword.has_key?(options, :body)
      refute Keyword.has_key?(options, :form_multipart)
    end

    test "does not pre-set multipart content-type header so adapter can add boundary", %{client: client} do
      operation =
        JSONOp.new(
          path: "/api/upload",
          http_method: :post,
          content_type: :multipart,
          data: %{file: {"content", filename: "file.txt"}}
        )

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:form_multipart] == %{file: {"content", filename: "file.txt"}}
      refute Map.has_key?(options[:headers], :content_type)
    end
  end

  describe "transformer integration" do
    test "applies transformer to response", %{client: client} do
      custom_transformer = fn response -> {:custom, response.body} end
      operation = JSONOp.new(path: "/api/test", transformer: custom_transformer)

      result = Operation.perform(operation, client, [])

      assert {:ok, {:custom, %{"response" => "ok"}}} = result
    end

    test "applies transform: false to disable transformation", %{client: client} do
      operation_transformer = fn response -> {:operation, response.body} end
      operation = JSONOp.new(path: "/api/test", transformer: operation_transformer)

      result = Operation.perform(operation, client, transform: false)

      assert {:ok, %Response{body: %{"response" => "ok"}}} = result
    end
  end

  describe "before_step callback integration" do
    test "return value rewrites the operation", %{client: client} do
      callback = fn operation, client, options ->
        rewritten_operation = %{
          operation
          | path: "/rewritten/path",
            headers: Map.put(operation.headers, :x_custom, ["injected-value"])
        }

        {rewritten_operation, client, options}
      end

      operation = JSONOp.new(path: "/original/path", before_step: callback)

      _result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:url].path == "/server/rewritten/path"
      assert options[:headers][:x_custom] == ["injected-value"]
    end

    test "can modify client properties", %{client: client} do
      callback = fn operation, client, options ->
        modified_client = %{client | csrf_token: "callback-injected-token"}
        {operation, modified_client, options}
      end

      operation = JSONOp.new(path: "/api/test", http_method: :post, before_step: callback)

      _result = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:headers][:x_xsrf_token] == ["callback-injected-token"]
    end
  end

  describe "version compatibility" do
    property "gates operation execution", %{client: client} do
      check all({test_client, supported_versions} <- client_and_requirements(client)) do
        operation = %JSONOp{
          path: "/test",
          supported_versions: supported_versions
        }

        resolved_version = Version.resolve(test_client)

        oracle_result = Version.check_compatibility(resolved_version, supported_versions)
        actual_result = Operation.perform(operation, test_client, [])

        case oracle_result do
          :ok ->
            assert {:ok, _response} = actual_result
            assert_received {:http_request, _options}

          {:error, _reason} ->
            assert {:error, %Error{}} = actual_result
            refute_received {:http_request, _options}
        end
      end
    end

    # compatibility check is opt-in
    test "passes when no version is specified in the client", %{client: client} do
      client = %{client | api_version: nil}

      operation = %JSONOp{
        path: "/test",
        supported_versions: %{cris: ">= 2023.1.1"}
      }

      result = Operation.perform(operation, client, [])

      assert {:ok, _response} = result
      assert_received {:http_request, _options}
    end

    test "treats versions it can't parse the same as when no version is specified", %{client: client} do
      client = %{client | api_version: "v9.01.beta3"}

      operation = %JSONOp{
        path: "/test",
        supported_versions: %{any: ">= 7.0.0"}
      }

      result = Operation.perform(operation, client, [])

      assert {:ok, _response} = result
      assert_received {:http_request, _options}
    end

    test "passes when the operation is supported", %{client: client} do
      client = %{client | api_version: "7.6.1"}

      operation = %JSONOp{
        path: "/test",
        supported_versions: %{any: ">= 7.0.0"}
      }

      result = Operation.perform(operation, client, [])

      assert {:ok, _response} = result
      assert_received {:http_request, _options}
    end

    test "passes for clients with api_version when supported by dspace",
         %{client: client} do
      client = %{client | api_version: "7.6.3"}

      operation = %JSONOp{
        path: "/test",
        supported_versions: %{dspace: ">= 7.6.3", cris: ">= 2023.1.1"}
      }

      result = Operation.perform(operation, client, [])

      assert {:ok, _response} = result
      assert_received {:http_request, _options}
    end

    test "fails for clients with api_version and no cris_version when supported by cris",
         %{client: client} do
      client = %{client | api_version: "7.6.1", cris_version: nil}

      operation = %JSONOp{
        path: "/test",
        supported_versions: %{cris: ">= 2023.1.1"}
      }

      result = Operation.perform(operation, client, [])

      assert {:error, %Error{}} = result
      refute_received {:http_request, _options}
    end

    test "passes for clients with cris_version when supported by cris",
         %{client: client} do
      client = %{client | cris_version: "2023.02.07"}

      operation = %JSONOp{
        path: "/test",
        supported_versions: %{dspace: "> 8.1.2", cris: ">= 2023.2.7"}
      }

      result = Operation.perform(operation, client, [])

      assert {:ok, _response} = result
      assert_received {:http_request, _options}
    end

    test "passes for clients with cris_version when supported by any distribution",
         %{client: client} do
      client = %{client | cris_version: "2023.02.07"}

      operation = %JSONOp{
        path: "/test",
        supported_versions: %{any: "> 7.6.2"}
      }

      result = Operation.perform(operation, client, [])

      assert {:ok, _response} = result
      assert_received {:http_request, _options}
    end

    test "returns an error when the operation is not supported instead of making a request",
         %{client: client} do
      client = %{client | api_version: "7.6.1"}

      operation = %JSONOp{
        path: "/test",
        supported_versions: %{cris: ">= 2023.1.1"}
      }

      result = Operation.perform(operation, client, [])

      assert {:error, %Error{}} = result
      refute_received {:http_request, _options}
    end

    test "raises when the version requirement is invalid", %{client: client} do
      client = %{client | cris_version: "2023.01.01"}

      operation = %JSONOp{
        path: "/test",
        # should be specified in normalized form: ">= 2023.1.1"
        supported_versions: %{cris: ">= 2023.01.01"}
      }

      assert_raise CaseClauseError, fn -> Operation.perform(operation, client, []) end
    end
  end

  describe "version overrides" do
    test "returns operation unchanged when api_version is nil", %{client: client} do
      client = %{client | api_version: nil}

      operation = %JSONOp{
        path: "/test",
        version_overrides: [{">= 7.0.0", [path: "/upgraded"]}]
      }

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:url].path == "/server/test"
    end

    test "returns operation unchanged when no overrides match", %{client: client} do
      client = %{client | api_version: "7.6.1"}

      operation = %JSONOp{
        path: "/test",
        version_overrides: [{">= 8.0.0", [path: "/upgraded"]}]
      }

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:url].path == "/server/test"
    end

    test "returns operation unchanged when version does not match dspace override", %{client: client} do
      dspace_client = %{client | api_version: "7.4.0"}

      operation = %JSONOp{
        path: "/test",
        version_overrides: [{%{dspace: ">= 8.0.0"}, [path: "/newer-dspace"]}]
      }

      assert {:ok, _} = Operation.perform(operation, dspace_client, [])

      assert_received {:http_request, options}
      assert options[:url].path == "/server/test"
    end

    test "returns operation unchanged when version does not match cris override", %{client: client} do
      cris_client = %{client | cris_version: "2023.01.01"}

      operation = %JSONOp{
        path: "/test",
        version_overrides: [{%{cris: ">= 2024.1.0"}, [path: "/newer-cris"]}]
      }

      assert {:ok, _} = Operation.perform(operation, cris_client, [])

      assert_received {:http_request, options}
      assert options[:url].path == "/server/test"
    end

    test "applies field override when version matches", %{client: client} do
      client = %{client | api_version: "7.5.0"}

      operation = %JSONOp{
        path: "/test",
        version_overrides: [{">= 7.5.0", [path: "/upgraded"]}]
      }

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:url].path == "/server/upgraded"
    end

    test "applies multiple overrides when both match", %{client: client} do
      client = %{client | api_version: "7.5.0"}

      operation = %JSONOp{
        path: "/test",
        http_method: :get,
        headers: %{},
        version_overrides: [
          {">= 7.0.0", [http_method: :post]},
          {">= 7.5.0", [headers: %{:x_test => ["value"]}]}
        ]
      }

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:method] == :post
      assert options[:headers][:x_test] == ["value"]
      assert options[:headers][:x_xsrf_token] == ["test-csrf-token"]
    end

    test "applies field override to cris client when version matches", %{client: client} do
      # CRIS 2023.01.01 maps to DSpace 7.5.0
      client = %{client | cris_version: "2023.01.01"}

      operation = %JSONOp{
        path: "/test",
        version_overrides: [{">= 7.0.0", [path: "/upgraded"]}]
      }

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:url].path == "/server/upgraded"
    end

    test "applies :any override to dspace client when version matches", %{client: client} do
      client = %{client | api_version: "7.6.0"}

      operation = %JSONOp{
        path: "/test",
        version_overrides: [{%{any: ">= 7.0.0"}, [path: "/upgraded"]}]
      }

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:url].path == "/server/upgraded"
    end

    test "applies :any override to cris client when version matches", %{client: client} do
      # CRIS 2023.01.01 maps to DSpace 7.5.0
      client = %{client | cris_version: "2023.01.01"}

      operation = %JSONOp{
        path: "/test",
        version_overrides: [{%{any: ">= 7.0.0"}, [path: "/upgraded"]}]
      }

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:url].path == "/server/upgraded"
    end

    test "applies :dspace override only to dspace client, not cris client", %{client: client} do
      dspace_client = %{client | api_version: "7.6.0"}
      # CRIS 2023.01.01 maps to DSpace 7.5.0, which would match >= 7.0.0 if checked
      cris_client = %{client | cris_version: "2023.01.01"}

      operation = %JSONOp{
        path: "/test",
        version_overrides: [{%{dspace: ">= 7.0.0"}, [path: "/dspace-only"]}]
      }

      assert {:ok, _} = Operation.perform(operation, dspace_client, [])
      assert_received {:http_request, options}
      assert options[:url].path == "/server/dspace-only"

      assert {:ok, _} = Operation.perform(operation, cris_client, [])
      assert_received {:http_request, options}
      assert options[:url].path == "/server/test"
    end

    test "applies :cris override only to cris client, not dspace client", %{client: client} do
      dspace_client = %{client | api_version: "7.6.0"}
      cris_client = %{client | cris_version: "2023.02.00"}

      operation = %JSONOp{
        path: "/test",
        version_overrides: [{%{cris: ">= 2023.1.1"}, [path: "/cris-only"]}]
      }

      assert {:ok, _} = Operation.perform(operation, cris_client, [])
      assert_received {:http_request, options}
      assert options[:url].path == "/server/cris-only"

      assert {:ok, _} = Operation.perform(operation, dspace_client, [])
      assert_received {:http_request, options}
      assert options[:url].path == "/server/test"
    end

    test "applies only :dspace override to dspace client", %{client: client} do
      client = %{client | api_version: "7.6.2"}

      operation = %JSONOp{
        path: "/test",
        http_method: :get,
        headers: %{},
        version_overrides: [
          {%{dspace: ">= 7.0.0"}, [http_method: :post]},
          {%{cris: ">= 2023.1.1"}, [headers: %{:x_test => ["value"]}]}
        ]
      }

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:method] == :post
      refute options[:headers][:x_test] == ["value"]
      assert options[:headers][:x_xsrf_token] == ["test-csrf-token"]
    end

    test "applies multiple overrides for different distributions when both match", %{client: client} do
      client = %{client | cris_version: "2023.01.01"}

      operation = %JSONOp{
        path: "/test",
        http_method: :get,
        headers: %{},
        version_overrides: [
          {%{any: ">= 7.0.0"}, [http_method: :post]},
          {%{cris: ">= 2023.1.1"}, [headers: %{:x_test => ["value"]}]}
        ]
      }

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:method] == :post
      assert options[:headers][:x_test] == ["value"]
      assert options[:headers][:x_xsrf_token] == ["test-csrf-token"]
    end

    test "handles invalid version specification gracefully", %{client: client} do
      client = %{client | api_version: "7.6.1"}

      operation = %JSONOp{
        path: "/test",
        version_overrides: [{"invalid-version-spec", [path: "/bad"]}]
      }

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:url].path == "/server/test"
    end

    test "supports version operators", %{client: client} do
      operation = %JSONOp{
        path: "/original",
        version_overrides: [
          {"< 7.5.0", [path: "/legacy"]},
          {"~> 7.6.0", [path: "/compatible"]},
          {"== 8.0.0", [path: "/exact"]}
        ]
      }

      client_74 = %{client | api_version: "7.4.0"}
      assert {:ok, _} = Operation.perform(operation, client_74, [])
      assert_received {:http_request, options}
      assert options[:url].path == "/server/legacy"

      client_762 = %{client | api_version: "7.6.2"}
      assert {:ok, _} = Operation.perform(operation, client_762, [])
      assert_received {:http_request, options}
      assert options[:url].path == "/server/compatible"

      client_800 = %{client | api_version: "8.0.0"}
      assert {:ok, _} = Operation.perform(operation, client_800, [])
      assert_received {:http_request, options}
      assert options[:url].path == "/server/exact"

      client_900 = %{client | api_version: "9.0.0"}
      assert {:ok, _} = Operation.perform(operation, client_900, [])
      assert_received {:http_request, options}
      assert options[:url].path == "/server/original"
    end

    test "handles overriding same field multiple times", %{client: client} do
      client = %{client | api_version: "7.5.0"}

      operation = %JSONOp{
        path: "/test",
        version_overrides: [
          {">= 7.0.0", [path: "/first"]},
          {">= 7.5.0", [path: "/second"]}
        ]
      }

      assert {:ok, _} = Operation.perform(operation, client, [])

      assert_received {:http_request, options}
      assert options[:url].path == "/server/second"
    end

    test "override upgrading GET to POST requires CSRF token", %{client: client} do
      client = %{client | api_version: "7.6.0", csrf_token: nil}

      operation = %JSONOp{
        path: "/test",
        http_method: :get,
        version_overrides: [{">= 7.0.0", [http_method: :post]}]
      }

      result = Operation.perform(operation, client, [])

      assert {:error, %Error{}} = result
      refute_received {:http_request, _options}
    end
  end

  # Private helpers

  # Generates a client with version info and a supported_versions map.
  defp client_and_requirements(base_client) do
    gen all(
          distribution <- member_of([:dspace, :cris]),
          client_version <- dspace_version_string(),
          requirement_key <- member_of([:any, :dspace, :cris]),
          requirement <- normalized_version_requirement()
        ) do
      test_client =
        case distribution do
          :dspace -> %{base_client | api_version: client_version, cris_version: nil}
          :cris -> %{base_client | api_version: nil, cris_version: to_cris_version(client_version)}
        end

      {test_client, %{requirement_key => requirement}}
    end
  end

  # Generates valid DSpace version strings like "7.6.1", "8.0.0"
  defp dspace_version_string do
    gen all(
          major <- integer(7..20),
          minor <- integer(0..9),
          patch <- integer(0..9)
        ) do
      "#{major}.#{minor}.#{patch}"
    end
  end

  # Generates valid version requirements
  defp normalized_version_requirement do
    gen all(
          operator <- member_of([">=", ">", "==", "~>"]),
          major <- integer(7..20),
          minor <- integer(0..9),
          patch <- integer(0..9),
          use_minor_only? <- if(operator == "~>", do: boolean(), else: constant(false))
        ) do
      version = if use_minor_only?, do: "#{major}.#{minor}", else: "#{major}.#{minor}.#{patch}"
      "#{operator} #{version}"
    end
  end

  # Converts a DSpace version string to a CRIS-style version string,
  # simplified mapping for test purposes
  defp to_cris_version(dspace_version) do
    [major, minor, _patch] = String.split(dspace_version, ".")
    major = String.to_integer(major)
    minor = String.to_integer(minor)

    year = 2021 + (major - 7)
    release = String.pad_leading("#{min(minor + 1, 12)}", 2, "0")
    "#{year}.#{release}.00"
  end
end
