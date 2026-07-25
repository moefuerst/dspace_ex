defmodule DSpace.API.Model do
  @moduledoc false
  @moduledoc since: "0.2.0"

  @typedoc """
  A map with string keys in wire format, with JSON-serializable values.
  """
  @type wire :: %{required(binary()) => term()}

  @doc """
  Creates a structure from a wire format map.
  """
  @callback from_map(wire()) :: struct()

  @doc """
  Creates a wire format map from a structure.
  """
  @callback to_map(struct()) :: wire()

  defmacro __using__(options) do
    quote location: :keep, bind_quoted: [options: options] do
      @behaviour DSpace.API.Model
      @before_compile DSpace.API.Model

      @dspace_model_options Keyword.validate!(options, drop_nil_on_wire: true)

      @impl DSpace.API.Model
      @spec to_map(struct()) :: %{required(binary()) => term()}
      def to_map(struct) when is_struct(struct, __MODULE__) do
        DSpace.API.Model.to_map(struct, @dspace_model_options)
      end

      defoverridable to_map: 1
    end
  end

  defmacro __before_compile__(env) do
    wire = Module.get_attribute(env.module, :wire)

    if not is_map(wire) do
      raise CompileError, file: env.file, description: "#{env.module} must set @wire to a map"
    end

    jason_impl =
      if Code.ensure_loaded?(Jason.Encoder) do
        quote do
          defimpl Jason.Encoder do
            def encode(struct, options) do
              struct
              |> @for.to_map()
              |> Jason.Encode.map(options)
            end
          end
        end
      end

    quote do
      @doc false
      @spec __wire__() :: %{optional(atom()) => binary()}
      def __wire__, do: unquote(Macro.escape(wire))

      defimpl JSON.Encoder do
        def encode(struct, encoder) do
          struct
          |> @for.to_map()
          |> JSON.Encoder.encode(encoder)
        end
      end

      unquote(if jason_impl, do: jason_impl)
    end
  end

  # API for internal use

  # This function is derived from Googly, see https://github.com/Rabbet/googly/blob/
  # c1ca0943e1042c75d221a0c0afb229bb593f077d/templates/client/encoder.ex.eex#L10-L20 The initial
  # developer is Matt Sutton. Copyright 2026 Rabbet, Inc. Googly source code is licensed under
  # the Apache License, Version 2.0, see https://github.com/Rabbet/googly/blob/main/LICENSE
  @spec to_map(struct(), keyword()) :: wire()
  def to_map(%{__struct__: module} = struct, options \\ []) do
    wire = module.__wire__()
    drop_nil = Keyword.get(options, :drop_nil_on_wire, true)

    struct
    |> Map.from_struct()
    |> Enum.reduce(%{}, fn
      {_k, nil}, acc when drop_nil == true -> acc
      {k, v}, acc -> Map.put(acc, Map.get(wire, k, Atom.to_string(k)), encode_value(v))
    end)
  end

  @spec encode_value(term()) :: term()
  def encode_value(%{__struct__: module} = value) when is_atom(module) do
    cond do
      function_exported?(module, :to_map, 1) -> module.to_map(value)
      function_exported?(module, :__wire__, 0) -> to_map(value)
      true -> Map.from_struct(value)
    end
  end

  def encode_value(value), do: value
end
