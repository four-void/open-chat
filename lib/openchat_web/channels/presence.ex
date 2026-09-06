defmodule OpenchatWeb.Presence do
  use Phoenix.Presence, otp_app: :openchat, pubsub_server: Openchat.PubSub
end
