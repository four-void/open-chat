defmodule Openchat.Security.Crypto do
  @moduledoc "Authenticated encryption for private database fields; keys live outside PostgreSQL."
  def encrypt(value) do
    iv = :crypto.strong_rand_bytes(12)

    {cipher, tag} =
      :crypto.crypto_one_time_aead(
        :aes_256_gcm,
        key(),
        iv,
        Jason.encode!(value),
        "openchat:v1",
        true
      )

    <<1, iv::binary, tag::binary, cipher::binary>>
  end

  def decrypt(<<1, iv::binary-size(12), tag::binary-size(16), cipher::binary>>) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key(), iv, cipher, "openchat:v1", tag, false) do
      :error -> raise "Invalid encrypted data"
      plain -> Jason.decode!(plain)
    end
  end

  def digest(value), do: :crypto.hash(:sha256, value)
  def blind(value), do: :crypto.mac(:hmac, :sha256, key(), value)
  def token, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  def password(value) do
    salt = :crypto.strong_rand_bytes(16)
    salt <> :crypto.pbkdf2_hmac(:sha256, value, salt, 600_000, 32)
  end

  def verify(value, <<salt::binary-size(16), hash::binary-size(32)>>),
    do: Plug.Crypto.secure_compare(hash, :crypto.pbkdf2_hmac(:sha256, value, salt, 600_000, 32))

  def verify(value, _), do: verify(value, <<0::384>>)

  defp key do
    case Application.fetch_env!(:openchat, :data_key) do
      <<_::256>> = key -> key
      _ -> raise "DATA_ENCRYPTION_KEY must decode to 32 bytes"
    end
  end
end
