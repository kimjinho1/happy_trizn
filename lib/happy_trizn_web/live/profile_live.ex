defmodule HappyTriznWeb.ProfileLive do
  @moduledoc """
  마이페이지 — 닉네임 수정 + 프로필 사진 업로드 + 미리보기.

  /me 라우트, 등록 사용자만 (게스트는 /lobby 리다이렉트).
  """

  use HappyTriznWeb, :live_view

  alias HappyTrizn.Accounts
  alias HappyTrizn.Avatars

  @max_size 2_000_000

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        {:ok, socket |> put_flash(:error, "로그인 사용자만") |> redirect(to: ~p"/lobby")}

      true ->
        changeset = Accounts.User.profile_changeset(user, %{})

        {:ok,
         socket
         |> assign(:page_title, "마이페이지")
         |> assign(:user, user)
         |> assign(:changeset, changeset)
         |> assign(:form, to_form(changeset))
         |> allow_upload(:avatar,
           accept: Avatars.allowed_exts(),
           max_entries: 1,
           max_file_size: @max_size
         )}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      socket.assigns.user
      |> Accounts.User.profile_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, changeset: changeset, form: to_form(changeset))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    user = socket.assigns.user

    # 1. avatar upload 가 있으면 priv/static/uploads/avatars/ 로 복사.
    {avatar_url, upload_err} = consume_avatar(socket, user.id)

    cond do
      upload_err ->
        {:noreply, put_flash(socket, :error, "사진 업로드 실패: #{upload_err}")}

      true ->
        attrs = Map.put(params, "avatar_url", avatar_url || user.avatar_url)

        case Accounts.update_profile(user, attrs) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> assign(:user, updated)
             |> assign(:changeset, Accounts.User.profile_changeset(updated, %{}))
             |> assign(:form, to_form(Accounts.User.profile_changeset(updated, %{})))
             |> put_flash(:info, "프로필 저장 완료")}

          {:error, changeset} ->
            {:noreply,
             socket
             |> assign(:changeset, changeset)
             |> assign(:form, to_form(changeset))
             |> put_flash(:error, "저장 실패 — 입력 확인")}
        end
    end
  end

  def handle_event("delete_avatar", _, socket) do
    user = socket.assigns.user
    Avatars.delete_existing(user.id)

    case Accounts.update_profile(user, %{"avatar_url" => nil}) do
      {:ok, updated} ->
        cs = Accounts.User.profile_changeset(updated, %{})

        {:noreply,
         socket
         |> assign(:user, updated)
         |> assign(:changeset, cs)
         |> assign(:form, to_form(cs))
         |> put_flash(:info, "프로필 사진 삭제됨")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "삭제 실패")}
    end
  end

  defp consume_avatar(socket, user_id) do
    uploads = uploaded_entries(socket, :avatar)

    case uploads do
      {[entry | _], _} ->
        try do
          url =
            consume_uploaded_entry(socket, entry, fn %{path: tmp_path} ->
              ext = Path.extname(entry.client_name) |> String.downcase()

              case Avatars.install(user_id, tmp_path, ext) do
                {:ok, url} -> {:ok, url}
                {:error, reason} -> {:postpone, reason}
              end
            end)

          {url, nil}
        rescue
          e -> {nil, Exception.message(e)}
        end

      _ ->
        {nil, nil}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto p-6">
      <h1 class="text-2xl font-bold mb-4">마이페이지</h1>

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <section class="bg-base-200 rounded p-4 mb-4">
        <h2 class="font-semibold mb-2 text-sm text-base-content/70">현재 프로필</h2>
        <div class="flex items-center gap-4">
          <.avatar_circle user={@user} size={80} />
          <div>
            <div class="text-lg font-bold">{@user.nickname}</div>
            <div class="text-xs text-base-content/60">{@user.email}</div>
          </div>
        </div>
      </section>

      <.form
        for={@form}
        phx-change="validate"
        phx-submit="save"
        class="space-y-4 bg-base-100 rounded p-4 border border-base-300"
      >
        <div>
          <label class="label">
            <span class="label-text">닉네임</span>
          </label>
          <input
            type="text"
            name="user[nickname]"
            value={@form[:nickname].value || @user.nickname}
            class="input input-bordered w-full"
            maxlength="32"
          />
          <%= if msg = error_message(@form, :nickname) do %>
            <span class="text-xs text-error">{msg}</span>
          <% end %>
        </div>

        <div>
          <label class="label">
            <span class="label-text">프로필 사진 (PNG / JPG / WEBP, 최대 2MB)</span>
          </label>
          <.live_file_input upload={@uploads.avatar} class="file-input file-input-bordered w-full" />
          <%= for entry <- @uploads.avatar.entries do %>
            <div class="flex items-center gap-2 mt-2">
              <.live_img_preview entry={entry} class="w-16 h-16 rounded-full object-cover" />
              <span class="text-sm">{entry.client_name}</span>
              <%= for err <- upload_errors(@uploads.avatar, entry) do %>
                <span class="text-xs text-error">{error_to_string(err)}</span>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="flex gap-2 pt-2">
          <button type="submit" class="btn btn-primary">저장</button>
          <%= if @user.avatar_url do %>
            <button
              type="button"
              phx-click="delete_avatar"
              data-confirm="프로필 사진 삭제?"
              class="btn btn-ghost"
            >
              사진 삭제
            </button>
          <% end %>
          <.link navigate={~p"/lobby"} class="btn btn-ghost ml-auto">로비로</.link>
        </div>
      </.form>
    </div>
    """
  end

  attr :user, :map, required: true
  attr :size, :integer, default: 40

  def avatar_circle(assigns) do
    ~H"""
    <%= if @user && @user.avatar_url do %>
      <img
        src={@user.avatar_url}
        alt={@user.nickname}
        class="rounded-full object-cover ring-2 ring-base-300"
        style={"width: #{@size}px; height: #{@size}px"}
      />
    <% else %>
      <div
        class="rounded-full bg-primary/20 flex items-center justify-center font-bold text-primary ring-2 ring-base-300"
        style={"width: #{@size}px; height: #{@size}px; font-size: #{div(@size, 2)}px"}
      >
        {avatar_initial(@user)}
      </div>
    <% end %>
    """
  end

  defp avatar_initial(nil), do: "?"

  defp avatar_initial(%{nickname: nick}) when is_binary(nick) and nick != "",
    do: String.first(nick) |> String.upcase()

  defp avatar_initial(_), do: "?"

  defp error_to_string(:too_large), do: "파일이 너무 큼 (최대 2MB)"
  defp error_to_string(:not_accepted), do: "허용 안 된 형식"
  defp error_to_string(:too_many_files), do: "1장만"
  defp error_to_string(other), do: to_string(other)

  defp error_message(form, field) do
    case form[field].errors do
      [{msg, _opts} | _] -> msg
      _ -> nil
    end
  end
end
