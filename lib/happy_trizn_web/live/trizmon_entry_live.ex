defmodule HappyTriznWeb.TrizmonEntryLive do
  @moduledoc """
  Trizmon 메인 entry (Sprint 5c-2c smoke).

  현재 = "1v1 PvE 미러 매치 시작" 버튼 1개.
  추후: 모험 / PvE 토너먼트 / PvP 친구 매칭 / 도감 / 파티 편성 등 진입.

  spec: docs/TRIZMON_SPEC.md §10, §17
  """

  use HappyTriznWeb, :live_view

  alias HappyTrizn.Trizmon.Party

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        {:ok, socket |> put_flash(:error, "Trizmon 은 로그인 사용자만. @trizn.kr 가입 필요.") |> redirect(to: ~p"/lobby")}

      true ->
        starter = Party.ensure_starter!(user)

        {:ok,
         socket
         |> assign(:user, user)
         |> assign(:starter, starter)
         |> assign(:page_title, "Trizmon")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto p-3 sm:p-6">
      <Layouts.flash_group flash={@flash} />
      <header class="mb-6">
        <h1 class="text-3xl font-bold">🐉 Trizmon</h1>
        <p class="text-sm text-base-content/60">자체 IP 몬스터 RPG. 현재 Sprint 5c-2c smoke.</p>
      </header>

      <section class="mb-6">
        <h2 class="text-lg font-semibold mb-2">내 시작 몬스터</h2>
        <div class="card bg-base-200">
          <div class="card-body p-4">
            <div class="flex items-center gap-3">
              <div class="text-4xl">🔥</div>
              <div>
                <div class="font-bold text-lg">{@starter.species.name_ko}</div>
                <div class="text-xs opacity-60">
                  Lv {@starter.level} · {@starter.species.type1}
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section class="mb-6">
        <h2 class="text-lg font-semibold mb-3">진입</h2>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <.link
            navigate={~p"/trizmon/battle"}
            class="card bg-primary text-primary-content shadow hover:scale-[1.02] transition"
          >
            <div class="card-body p-4">
              <h3 class="font-bold text-lg">⚔️ PvE 1v1 (smoke)</h3>
              <p class="text-xs opacity-90">CPU 와 미러 매치. 5c-2c 검증용.</p>
            </div>
          </.link>

          <.link
            navigate={~p"/trizmon/adventure"}
            class="card bg-secondary text-secondary-content shadow hover:scale-[1.02] transition"
          >
            <div class="card-body p-4">
              <h3 class="font-bold text-lg">🗺️ 모험 모드</h3>
              <p class="text-xs opacity-90">시작 마을 + 이동. 인카운터 = 5c-3b</p>
            </div>
          </.link>

          <div class="card bg-base-300 shadow opacity-60">
            <div class="card-body p-4">
              <h3 class="font-bold text-lg">🤝 PvP (친구)</h3>
              <p class="text-xs">Sprint 5c-5 — 친구 매칭 + 3v3/6v6</p>
            </div>
          </div>

          <div class="card bg-base-300 shadow opacity-60">
            <div class="card-body p-4">
              <h3 class="font-bold text-lg">📖 도감</h3>
              <p class="text-xs">Sprint 5c-6 — 본/잡은 종 표시</p>
            </div>
          </div>
        </div>
      </section>

      <p class="text-xs text-base-content/40 mt-6">
        spec: <code>docs/TRIZMON_SPEC.md</code> · 진행: PR <a href="https://github.com/kimjinho1/happy_trizn/pull/43" class="link">#43</a>
      </p>
    </div>
    """
  end
end
