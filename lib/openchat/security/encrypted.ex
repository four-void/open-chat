defmodule Openchat.Security.Encrypted do
  use Ecto.Type
  def type, do: :binary
  def cast(value) when is_map(value), do: {:ok, value}
  def cast(_), do: :error
  def load(value), do: {:ok, Openchat.Security.Crypto.decrypt(value)}
  def dump(value) when is_map(value), do: {:ok, Openchat.Security.Crypto.encrypt(value)}
  def dump(_), do: :error
end
