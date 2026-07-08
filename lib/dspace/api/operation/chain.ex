defmodule DSpace.API.Operation.Chain do
  @moduledoc """
  Represents a chain of operations executed sequentially against the DSpace API.

  This module is usually not used directly. Operation data structures are constructed by API
  operation modules. Building your own operations is useful in cases where dspace_ex doesn't
  support a specific API functionality yet.

  A chain is useful when one API interaction depends on another, e.g. when the result of a first
  request parameterizes a second one, or when a request needs a value to be fetched before it can
  be made. Each step is a link function that receives the result of the previous step and a
  context struct, and decides which operation to perform next. Execution short-circuits at the
  first error.
  """

  defstruct steps: []

  @type t :: %__MODULE__{
          steps: [link()]
        }

  @typedoc """
  A link function for a chain step.

    * `prev_result` - result of the previous step. The first step receives `nil`.
    * `ctx` - threaded context carrying the client and the request options. A link may return an
      updated context.

  Returning `{operation, ctx}` runs `operation` and passes its result to the next step. Returning
  `{:skip, ctx}` runs nothing for this step and passes `prev_result` through unchanged.
  """
  @type link :: (prev_result :: term(), ctx :: DSpace.API.Operation.Chain.Context.t() ->
                   {operation :: DSpace.API.Operation.t(), ctx :: DSpace.API.Operation.Chain.Context.t()}
                   | {:skip, ctx :: DSpace.API.Operation.Chain.Context.t()})

  defmodule Context do
    @moduledoc """
    Context for a chain operation, holding the client and request options.
    """
    defstruct [:client, :options]

    @type t :: %__MODULE__{
            client: DSpace.API.t(),
            options: keyword()
          }
  end

  # Public API

  @doc """
  Creates a new chain operation from a list of link functions.
  """
  @spec new([link()]) :: t()
  def new(steps) when is_list(steps) do
    struct(__MODULE__, steps: steps)
  end
end

defimpl DSpace.API.Operation, for: DSpace.API.Operation.Chain do
  alias DSpace.API
  alias DSpace.API.Operation
  alias DSpace.API.Operation.Chain
  alias DSpace.API.Operation.Chain.Context

  # Options that shape the final result and should only be applied to the last step.
  @reserved_options [:transform, :into, :decode_json]

  @spec perform(Chain.t(), API.t(), keyword()) :: {:ok, term()} | {:error, Exception.t()}
  def perform(%Chain{steps: steps}, client, options) do
    reserved_options = Keyword.take(options, @reserved_options)
    options = Keyword.drop(options, @reserved_options)

    run_steps(steps, nil, %Context{client: client, options: options}, reserved_options)
  end

  @spec stream!(Chain.t(), API.t(), keyword()) :: no_return()
  def stream!(%Chain{}, _client, _options) do
    raise ArgumentError, "this operation cannot be streamed"
  end

  # Private helpers

  # Reserved options apply only to the final step, matched here as `[step]`. Earlier steps
  # pass `[]`, so the merge in `perform_step/3` is a no-op.
  defp run_steps([step], prev_result, context, reserved_options) do
    case run_step(step, prev_result, context, reserved_options) do
      {:ok, {result, _context}} -> {:ok, result}
      {:error, _reason} = error -> error
    end
  end

  defp run_steps([step | rest], prev_result, context, reserved_options) do
    case run_step(step, prev_result, context, []) do
      {:ok, {result, context}} -> run_steps(rest, result, context, reserved_options)
      {:error, _reason} = error -> error
    end
  end

  defp run_step(step, prev_result, context, reserved_options) do
    case step.(prev_result, context) do
      {:skip, %Context{} = context} -> {:ok, {prev_result, context}}
      {operation, %Context{} = context} -> perform_step(operation, context, reserved_options)
    end
  end

  defp perform_step(operation, context, reserved_options) do
    options = Keyword.merge(context.options, reserved_options)

    case Operation.perform(operation, context.client, options) do
      {:ok, result} -> {:ok, {result, context}}
      {:error, _reason} = error -> error
    end
  end
end
