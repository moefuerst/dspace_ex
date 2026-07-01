defmodule DSpace.API.Operation.ChainTest do
  use ExUnit.Case, async: true

  alias DSpace.API
  alias DSpace.API.HTTP.Response
  alias DSpace.API.Operation
  alias DSpace.API.Operation.Chain
  alias DSpace.API.Operation.JSON, as: JSONOp

  setup do
    client =
      %API{
        endpoint: "https://example.com/server",
        http_impl: {TestHelper.HTTP, []}
      }

    {:ok, client: client}
  end

  describe "perform/3" do
    test "runs steps sequentially, feeding each result into the next", %{client: client} do
      chain =
        Chain.new([
          fn nil, ctx ->
            {JSONOp.new(path: "/step1", transformer: fn _ -> :first end), ctx}
          end,
          fn prev_result, ctx ->
            assert prev_result == :first
            {JSONOp.new(path: "/step2", transformer: fn _ -> :second end), ctx}
          end
        ])

      assert {:ok, :second} = Operation.perform(chain, client, [])

      assert_received {:http_request, step1_options}
      assert_received {:http_request, step2_options}
      assert String.ends_with?(step1_options[:url].path, "/step1")
      assert String.ends_with?(step2_options[:url].path, "/step2")
    end

    test "threads an updated client through the context", %{client: client} do
      chain =
        Chain.new([
          fn nil, ctx ->
            {JSONOp.new(path: "/token", transformer: fn _ -> "fetched-token" end), ctx}
          end,
          fn token, ctx ->
            ctx = %{ctx | client: %{ctx.client | csrf_token: token}}
            {JSONOp.new(path: "/login", http_method: :post, data: %{}), ctx}
          end
        ])

      assert {:ok, _} = Operation.perform(chain, client, [])

      assert_received {:http_request, _token_options}
      assert_received {:http_request, login_options}
      assert login_options[:headers][:x_xsrf_token] == ["fetched-token"]
    end

    test ":skip step passes the previous result through without a request", %{client: client} do
      chain =
        Chain.new([
          fn nil, ctx -> {:skip, ctx} end,
          fn prev_result, ctx ->
            assert prev_result == nil
            {JSONOp.new(path: "/only", transformer: fn _ -> :done end), ctx}
          end
        ])

      assert {:ok, :done} = Operation.perform(chain, client, [])

      assert_received {:http_request, options}
      assert String.ends_with?(options[:url].path, "/only")
      refute_received {:http_request, _other}
    end

    test "halts and returns the error as-is when a step fails", %{client: client} do
      chain =
        Chain.new([
          fn nil, ctx ->
            {JSONOp.new(path: "/boom", transformer: fn _ -> {:error, :boom} end), ctx}
          end,
          fn _prev_result, ctx ->
            {JSONOp.new(path: "/never"), ctx}
          end
        ])

      assert {:error, :boom} = Operation.perform(chain, client, [])

      assert_received {:http_request, _boom_options}
      refute_received {:http_request, _never_options}
    end
  end

  describe "option handling" do
    test "propagates transport options to every step", %{client: client} do
      chain =
        Chain.new([
          fn nil, ctx -> {JSONOp.new(path: "/step1"), ctx} end,
          fn _prev, ctx -> {JSONOp.new(path: "/step2"), ctx} end
        ])

      assert {:ok, _} = Operation.perform(chain, client, retry: false)

      assert_received {:http_request, step1_options}
      assert_received {:http_request, step2_options}
      assert step1_options[:retry] == false
      assert step2_options[:retry] == false
    end

    test "applies :transform only to the final step", %{client: client} do
      chain =
        Chain.new([
          fn nil, ctx ->
            # Intermediate step must transform so its result can feed the next link.
            {JSONOp.new(path: "/step1", transformer: fn %Response{} -> :transformed end), ctx}
          end,
          fn prev_result, ctx ->
            assert prev_result == :transformed
            {JSONOp.new(path: "/step2"), ctx}
          end
        ])

      # transform: false means the final step returns the raw response, untransformed.
      assert {:ok, %Response{}} = Operation.perform(chain, client, transform: false)
    end

    test "applies :into only to the final step", %{client: client} do
      chain =
        Chain.new([
          fn nil, ctx -> {JSONOp.new(path: "/step1"), ctx} end,
          fn _prev, ctx -> {JSONOp.new(path: "/step2"), ctx} end
        ])

      assert {:ok, _} = Operation.perform(chain, client, into: :sentinel)

      assert_received {:http_request, step1_options}
      assert_received {:http_request, step2_options}
      refute Keyword.has_key?(step1_options, :into)
      assert step2_options[:into] == :sentinel
    end
  end
end
