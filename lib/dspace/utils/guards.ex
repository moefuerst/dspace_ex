defmodule DSpace.Utils.Guards do
  @moduledoc false

  defguard is_not_empty(term) when is_binary(term) and byte_size(term) > 0
end
