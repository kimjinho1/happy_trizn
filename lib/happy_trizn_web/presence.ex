defmodule HappyTriznWeb.Presence do
  @moduledoc """
  Phoenix.Presence — 접속 중인 사용자 추적.

  fetch_live_user hook 이 LiveView mount 시 user_id 로 track. 로그아웃/연결
  종료 시 자동 untrack. 친구 list 등 다른 LV 에서 `online_user_ids/0` 또는
  `online?/1` 로 조회.

  Topic: "users:online" — diff broadcast 받고 싶은 LV 가 subscribe.
  """

  use Phoenix.Presence,
    otp_app: :happy_trizn,
    pubsub_server: HappyTrizn.PubSub

  @topic "users:online"

  @doc "이 LV 가 사용자 user 의 presence 를 track. 연결 종료 시 자동 untrack."
  def track_user(pid, user_id) when is_binary(user_id) do
    track(pid, @topic, user_id, %{
      online_at: System.system_time(:second)
    })
  end

  def track_user(_, _), do: :ignore

  @doc "현재 접속 중 user_id MapSet."
  def online_user_ids do
    @topic
    |> list()
    |> Map.keys()
    |> MapSet.new()
  end

  @doc "특정 user_id 접속 중?"
  def online?(user_id) when is_binary(user_id) do
    @topic |> list() |> Map.has_key?(user_id)
  end

  def online?(_), do: false

  @doc "presence diff 구독 — \"presence_diff\" tuple 메시지 받음."
  def subscribe do
    Phoenix.PubSub.subscribe(HappyTrizn.PubSub, @topic)
  end

  def topic, do: @topic
end
