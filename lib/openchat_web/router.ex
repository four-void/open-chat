defmodule OpenchatWeb.Router do
  use OpenchatWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {OpenchatWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug OpenchatWeb.SecurityHeaders
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug OpenchatWeb.SecurityHeaders
  end

  scope "/api", OpenchatWeb do
    pipe_through :api
    get "/session", ApiController, :session
    post "/register", ApiController, :register
    post "/login", ApiController, :login
    delete "/session", ApiController, :logout
    put "/vault", ApiController, :vault
    get "/profile/username", ApiController, :username_available
    put "/profile", ApiController, :profile
    put "/account/credentials", ApiController, :credentials
    get "/friends", ApiController, :friends
    post "/friends", ApiController, :friend_request
    put "/friends/:id", ApiController, :friend_accept
    delete "/friends/:id", ApiController, :friend_delete
    get "/servers", ApiController, :servers
    post "/servers", ApiController, :create_server
    get "/servers/:id/rooms", ApiController, :rooms
    get "/servers/:id/members", ApiController, :members
    post "/servers/:id/rooms", ApiController, :create_room
    post "/servers/:id/invites", ApiController, :invite
    post "/invites/accept", ApiController, :accept
    get "/rooms/:id/messages", ApiController, :messages
    get "/servers/:id/roles", ApiController, :roles
    post "/servers/:id/roles", ApiController, :save_role
    put "/servers/:id/role-order", ApiController, :reorder_roles
    delete "/servers/:id/roles/:role_id", ApiController, :delete_role
    put "/servers/:id/roles/:role_id", ApiController, :save_role
    put "/servers/:id/everyone", ApiController, :everyone
    put "/servers/:id/members/:user_id/roles/:role_id", ApiController, :set_member_role
    put "/servers/:id/members/:user_id/roles", ApiController, :assign_roles
    get "/rooms/:id/permissions", ApiController, :room_permissions
    put "/rooms/:id/permissions", ApiController, :save_room_permissions
    post "/messages/:id/thread", ApiController, :create_thread
    get "/rooms/:id/threads", ApiController, :threads
    get "/threads/:id/messages", ApiController, :thread_messages
    patch "/threads/:id", ApiController, :archive_thread
    put "/direct/identity", ApiController, :direct_identity
    get "/direct/contacts", ApiController, :direct_contacts
    get "/direct", ApiController, :direct_list
    post "/direct", ApiController, :direct_start
    get "/direct/:id/messages", ApiController, :direct_history
    post "/direct/:id/messages", ApiController, :direct_send
    patch "/messages/:id", ApiController, :edit_message
    delete "/messages/:id", ApiController, :delete_message
    put "/messages/:id/reaction", ApiController, :react_message
    patch "/direct/messages/:id", ApiController, :edit_message
    delete "/direct/messages/:id", ApiController, :delete_message
    put "/direct/messages/:id/reaction", ApiController, :react_message
    get "/ice", ApiController, :ice
  end

  scope "/", OpenchatWeb do
    pipe_through :browser
    get "/friends", PageController, :home
    get "/messages", PageController, :home
    get "/profile", PageController, :home
    get "/", PageController, :home
  end
end
