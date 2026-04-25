defmodule HappyTriznWeb.RegistrationHTML do
  @moduledoc false
  use HappyTriznWeb, :html

  embed_templates "registration_html/*"

  @doc "Tailwind error class for input field with errors."
  def error_class(%Ecto.Changeset{} = cs, field) do
    if Keyword.has_key?(cs.errors, field) and cs.action != nil, do: "input-error", else: ""
  end

  def error_class(_, _), do: ""

  @doc "First error message for the field, or nil."
  def error_msg(%Ecto.Changeset{} = cs, field) do
    case cs.errors[field] do
      {msg, opts} when cs.action != nil ->
        Enum.reduce(opts, msg, fn {k, v}, acc ->
          String.replace(acc, "%{#{k}}", to_string(v))
        end)

      _ ->
        nil
    end
  end

  def error_msg(_, _), do: nil
end
