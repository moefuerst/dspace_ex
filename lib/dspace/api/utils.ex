defmodule DSpace.API.Utils do
  @moduledoc false

  # Public API

  defguard is_nonempty_binary(term) when is_binary(term) and byte_size(term) > 0
end
