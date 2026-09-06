import Config

if System.get_env("PHX_SERVER"), do: config(:openchat, OpenchatWeb.Endpoint, server: true)

key = System.get_env("DATA_ENCRYPTION_KEY")

if key && byte_size(Base.decode64!(key)) != 32,
  do: raise("DATA_ENCRYPTION_KEY must contain 32 bytes")

if config_env() == :prod and is_nil(key), do: raise("DATA_ENCRYPTION_KEY is required")

config :openchat,
       :data_key,
       if(key,
         do: Base.decode64!(key),
         else: :crypto.hash(:sha256, "openchat-local-development-only")
       )

config :openchat, :turn_urls, String.split(System.get_env("TURN_URLS") || "", ",", trim: true)
config :openchat, :turn_secret, System.get_env("TURN_SECRET")

if config_env() == :prod do
  config :openchat, Openchat.Repo,
    url: System.fetch_env!("DATABASE_URL"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    log: false

  host = System.fetch_env!("PHX_HOST")

  config :openchat, OpenchatWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    check_origin: ["https://" <> host],
    force_ssl: [rewrite_on: [:x_forwarded_proto]],
    http: [ip: {0, 0, 0, 0}, port: String.to_integer(System.get_env("PORT") || "4000")],
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE")
end
