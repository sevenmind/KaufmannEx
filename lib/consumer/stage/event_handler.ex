defmodule KaufmannEx.Consumer.Stage.EventHandler do
  @moduledoc """
  Behavior module for consuming messages from Kafka bus.

  Spawns tasks to process each event. Should still be within the KaufmannEx supervision tree.
  """
  require Logger
  use Elixometer

  def start_link(event) do
    Task.start_link(fn ->
      handle_event(event)
    end)
  end

  @timed key: :auto
  def handle_event(event) do
    try do
      handler = KaufmannEx.Config.event_handler()

      event
      |> handler.given_event()
    rescue
      error ->
        Logger.warn("Error Consuming #{inspect(event)} #{inspect(error)}")
        handler = KaufmannEx.Config.event_handler()

        event
        |> error_from_event(error)
        |> handler.given_event()

        reraise error, __STACKTRACE__
    end
  end

  # if loop of error events, just emit whatever we got
  defp error_from_event(%KaufmannEx.Schemas.ErrorEvent{} = event, _error) do
    event
  end

  defp error_from_event(event, error) do
    %KaufmannEx.Schemas.ErrorEvent{
      name: event.name,
      error: inspect(error),
      message_payload: event.payload,
      meta: event.meta
    }
  end
end
