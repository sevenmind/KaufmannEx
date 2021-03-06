defmodule KaufmannEx.Config do
  @moduledoc """
  Convenience Getters for pulling config.exs values

  A config.exs may look like
  ```
  # test env
  config :kaufmann_ex,
    consumer_group: System.get_env("CONSUMER_GROUP"),
    default_topic: System.get_env("KAFKA_TOPIC"),
    max_demand: 1, # batch size leave at 1 for slow topics.
    stages: 16,
    event_handler_mod: nil, # Be sure to specify your event handler
    gen_consumer_mod: KaufmannEx.Consumer.GenConsumer,
    producer_mod: KaufmannEx.Publisher,
    schema_path: "priv/schemas",
    schema_registry_uri: System.get_env("SCHEMA_REGISTRY_PATH"),
    service_id: System.get_env("HOSTNAME"),
    service_name: "SampleService"
  ```
  """

  @doc """
    `Application.get_env(:kaufmann_ex, :consumer_group)`
  """
  @spec consumer_group() :: String.t() | nil
  def consumer_group, do: Application.get_env(:kaufmann_ex, :consumer_group)

  @doc """
    `Application.get_env(:kaufmann_ex, :default_topic)`
  """
  @spec default_topic() :: String.t() | nil
  def default_topic, do: Application.get_env(:kaufmann_ex, :default_topic)

  @doc """
    `default_topic/0` in a list

    `[KaufmannEx.Config.default_topic()]`
  """
  @spec default_topics() :: [String.t()]
  def default_topics, do: Application.get_env(:kaufmann_ex, :default_topics, [default_topic()])

  @doc """
    `Application.get_env(:kaufmann_ex, :subscription_topics, default_topics())`

    Determines which topics the Kaufmann Supervisor will subscribe to
  """
  @spec subscription_topics() :: [String.t()]
  def subscription_topics,
    do: Application.get_env(:kaufmann_ex, :subscription_topics, default_topics())

  @spec default_publish_topic() :: String.t() | nil
  def default_publish_topic,
    do: Application.get_env(:kaufmann_ex, :default_publish_topic, default_topic())

  @doc """
  `Application.get_env(:kaufmann_ex, :event_handler_mod)`
  """
  @spec event_handler() :: atom | nil
  def event_handler, do: Application.get_env(:kaufmann_ex, :event_handler_mod)

  @doc """
  `Application.get_env(:kaufmann_ex, :producer_mod)`
  """
  @spec producer_mod() :: atom | nil
  def producer_mod, do: Application.get_env(:kaufmann_ex, :producer_mod, KaufmannEx.Publisher)

  @doc """
  `Application.get_env(:kaufmann_ex, :schema_path)`
  """
  @spec schema_path() :: [String.t() | nil]
  def schema_path,
    do: List.flatten([Application.get_env(:kaufmann_ex, :schema_path, "priv/schemas")])

  @doc """
  `Application.get_env(:kaufmann_ex, :schema_registry_uri)`
  """
  @spec schema_registry_uri() :: String.t() | nil
  def schema_registry_uri, do: Application.get_env(:kaufmann_ex, :schema_registry_uri)

  @doc """
  `Application.get_env(:kaufmann_ex, :service_name)`
  """
  @spec service_name() :: String.t() | nil
  def service_name, do: Application.get_env(:kaufmann_ex, :service_name)

  @doc """
  `Application.get_env(:kaufmann_ex, :service_id)`
  """
  @spec service_id() :: String.t() | nil
  def service_id, do: Application.get_env(:kaufmann_ex, :service_id)

  @doc """
  Application.get_env(:kaufmann_ex, :max_demand, 1)
  """
  @spec max_demand() :: integer()
  def max_demand, do: Application.get_env(:kaufmann_ex, :max_demand, 1)

  @doc """
  Application.get_env(:kaufmann_ex, :max_demand, 1)
  """
  @spec stages() :: integer()
  def stages, do: Application.get_env(:kaufmann_ex, :stages, 16)

  @doc """
  Application.get_env(:kaufmann_ex, :gen_consumer_mod)
  """
  @spec gen_consumer_mod() :: atom
  def gen_consumer_mod,
    do: Application.get_env(:kaufmann_ex, :gen_consumer_mod, KaufmannEx.Consumer.GenConsumer)

  @doc """
  Partition selection strategy, default is :random, options are `[:random]
   Application.get_env(:kaufmann_ex, :partition_strategy, :random)
  """
  @spec partition_strategy() :: :random | :md5
  def partition_strategy, do: Application.get_env(:kaufmann_ex, :partition_strategy, :random)

  @doc """
  partitioning strategy, only option is default
  """
  @spec topic_strategy() :: :default
  def topic_strategy, do: Application.get_env(:kaufmann_ex, :topic_strategy, :default)

  @spec schema_cache_expires_in_ms() :: integer
  def schema_cache_expires_in_ms,
    do: Application.get_env(:kaufmann_ex, :schema_cache_expires_in_ms, 10 * 60 * 1000)

  def commit_strategy, do: Application.get_env(:kaufmann_ex, :commit_strategy, :async_commit)

  @spec transcoder(atom) :: atom
  def transcoder(format),
    do:
      :kaufmann_ex
      |> Application.get_env(:transcoder)
      |> Keyword.get(format)

  def transcoders,
    do:
      :kaufmann_ex
      |> Application.get_env(:transcoder)
      |> Keyword.values()
end
