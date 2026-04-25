defmodule HappyTriznWeb.PageController do
  use HappyTriznWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
