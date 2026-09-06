defmodule Openchat.PlatformFixtures do
  def vault,
    do: %{
      "iv" => Base.encode64(:crypto.strong_rand_bytes(12)),
      "cipher" => Base.encode64(:crypto.strong_rand_bytes(32))
    }

  def params do
    %{
      "email" => "person#{System.unique_integer([:positive])}@example.fr",
      "name" => "Camille",
      "password" => "a long test password",
      "salt" => Base.encode64(:crypto.strong_rand_bytes(16)),
      "vault" => vault()
    }
  end

  def user do
    {:ok, user} = Openchat.Accounts.register(params())
    user
  end

  def message, do: Map.put(vault(), "nonce", Ecto.UUID.generate())
end
