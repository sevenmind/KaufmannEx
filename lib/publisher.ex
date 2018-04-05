defmodule KaufmannEx.Publisher do
  @moduledoc """
    Publishes Avro encoded messages to the default topic (`KaufmannEx.Config.default_topic/0`).


  """
  require Logger
  alias KafkaEx.Protocol.Produce.Message
  alias KafkaEx.Protocol.Produce.Request

  def default_topic do
    KaufmannEx.Config.default_topic() || "default_topic"
  end

  @spec produce(atom(), term()) :: :ok | {:error, any}
  def produce(message_name, payload) when is_atom(message_name) do
    produce(default_topic(), Atom.to_string(message_name), payload)
  end

  @doc """
  calls `produce/3` with with the default topic
  """
  @spec produce(String.t(), term()) :: :ok | {:error, any}
  def produce(message_name, payload) when is_binary(message_name) do
    produce(default_topic(), message_name, payload)
  end

  @doc """
  Publishes encoded message

  Encodes messages into Avro Schema with ` KaufmannEx.Schemas.encode_message/2`

  Defaults to partition 0 for publication. This is less than ideal.
  """
  @spec produce(String.t(), String.t(), term()) :: :ok | {:error, any}
  def produce(topic, message_name, data) do
    with {:ok, payload} <- KaufmannEx.Schemas.encode_message(message_name, data) do
      Logger.debug(fn -> "Publishing Event #{message_name} on #{topic}" end)
      message = %Message{value: payload, key: message_name}

      # TODO: Pull Partition Info from somewhere
      # maybe choose random partition or use md5 hash of message?
      produce_request = %Request{
        partition: 0,
        topic: topic,
        messages: [message]
      }

      KafkaEx.produce(produce_request)
    else
      {:error, error} ->
        publish_error(message_name, error, data.payload, data.meta)

      {:error, error, _} ->
        publish_error(message_name, error, data.payload, data.meta)
    end
  end

  @doc """
  Replace "command." with "event." in event names
  """
  @spec cmd_to_event(atom) :: atom
  def cmd_to_event(command_name) do
    command_name
    |> to_string
    |> String.replace_prefix("command.", "event.")
    |> String.to_atom()
  end

  @doc """
    Publishes error for a given event

    prepends the message_name with "event.error"
  """
  @spec publish_error(String.t() | atom, any, any, any) :: :ok | {:error, any}
  def publish_error(event_name, error, _orig_payload, meta \\ %{}) do
    error_payload = %{
      error: error
    }

    publish(:"event.error.#{event_name}", error_payload, meta)
  end

  @doc """
    Publishes error for a given event

    prepends the message_name with "event.error"
  """
  @spec publish_error(KaufmannEx.Schemas.Event.t(), term) :: :ok | {:error, any}
  def publish_error(%KaufmannEx.Schemas.Event{} = event, error) do
    error_payload = %{
      error: error
    }

    publish(:"event.error.#{event.name}", error_payload, event.meta)
  end

  @doc """
  Injects metadata then calls `produce/2`

  Inserted metadata conforms to the `event_metadata/2`

  Events with Metadata are produced to the Producer set in config `:kaufmann_ex, :producer_mod`. This defaults to `KaufmannEx.Publisher`
  """
  @spec publish(atom, map, map) :: :ok
  def publish(event_name, payload, context \\ %{}) do
    message_body = %{
      payload: payload,
      meta: event_metadata(event_name, context)
    }

    producer = Application.fetch_env!(:kaufmann_ex, :producer_mod)

    producer.produce(event_name, message_body)
  end

  @doc """
  generate metadata for an event

  ```
  %{
      message_id: Nanoid.generate(),
      emitter_service: KaufmannEx.Config.service_name(), # env var SERVICE_NAME
      emitter_service_id: KaufmannEx.Config.service_id(), # env var HOST_NAME
      callback_id: context[:callback_id],
      message_name: event_name |> to_string,
      timestamp: DateTime.to_string(DateTime.utc_now())
    }
  ```
  """
  @spec event_metadata(atom, map) :: map
  def event_metadata(event_name, context) do
    log_time_took(context[:timestamp], event_name)

    %{
      message_id: Nanoid.generate(),
      emitter_service: KaufmannEx.Config.service_name(),
      emitter_service_id: KaufmannEx.Config.service_id(),
      callback_id: context[:callback_id],
      message_name: event_name |> to_string,
      timestamp: DateTime.to_string(DateTime.utc_now())
    }
  end

  defp log_time_took(nil, _), do: nil

  defp log_time_took(timestamp, event_name) do
    {:ok, published_at, _} = DateTime.from_iso8601(timestamp)
    took = DateTime.diff(DateTime.utc_now(), published_at, :millisecond)

    Logger.info(fn -> "Responded with #{event_name} in #{took}ms" end)
  end
end
