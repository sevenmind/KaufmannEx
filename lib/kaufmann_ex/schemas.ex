defmodule KaufmannEx.Schemas do
  @moduledoc """
    Handles registration, retrieval, validation and parsing of Avro Schemas.

    Schemas are cached to ETS table using `Memoize`. Does not handle schema changes while running. Best practice is to redeploy all services using a message schema if the schema changes.

    Depends on
     - `Schemex` - calls to Confluent Schema Registry
     - `AvroEx` - serializing and deserializing avro encoded messages
     - `Memoize` - Cache loading schemas to an ETS table, prevent performance bottleneck at schema registry.
  """

  use Memoize
  require Logger
  require Map.Helpers
  alias KaufmannEx.Schemas.Event

  @spec decode_event(map) :: KaufmannEx.Schemas.Event.t() | KaufmannEx.Schemas.ErrorEvent.t()
  def decode_event(%Event{raw_event: %{key: key, value: value}} = event) do
    event_name = key |> String.to_atom()
    crc = Map.get(event, :crc)
    now = DateTime.utc_now()
    size = byte_size(value)

    case decode_message(key, value) do
      {:ok, %{meta: meta, payload: payload}} ->
        {:ok, published_at, _} = DateTime.from_iso8601(meta[:timestamp])
        bus_time = DateTime.diff(now, published_at, :millisecond)

        Logger.debug([
          to_string(key),
          " ",
          to_string(meta[:message_id]),
          " from ",
          to_string(meta[:emitter_service_id]),
          " on ",
          to_string(event.topic),
          "@",
          to_string(event.partition),
          " in ",
          to_string(bus_time),
          "ms ",
          to_string(size),
          " bytes"
        ])

        %KaufmannEx.Schemas.Event{
          event
          | name: event_name,
            meta: Map.put(meta, :crc, crc),
            payload: payload
        }

      {:error, error} ->
        Logger.warn(fn -> "Error Decoding #{key} #{inspect(error)}" end)

        err_event =
          event
          |> Map.from_struct()
          |> Map.merge(%{name: key, error: error, message_payload: value})

        struct(KaufmannEx.Schemas.ErrorEvent, err_event)
    end
  end

  @spec encode_message(String.t(), Map) :: {atom, any}
  def encode_message(message_name, payload) do
    with {:ok, schema} <- parsed_schema(message_name) do
      stringified = Map.Helpers.stringify_keys(payload)
      encode_message_with_schema(schema, stringified)
    else
      {:error, error_message} ->
        Logger.warn(fn -> "Error Encoding #{message_name}, #{inspect(payload)}" end)

        {:error, {:schema_encoding_error, error_message}}
    end
  end

  @spec decode_message(String.t(), binary) :: {atom, any}
  def decode_message(message_name, encoded) do
    with {:ok, schema} <- parsed_schema(message_name) do
      schema
      |> decode_message_with_schema(encoded)
      |> atomize_keys()
    else
      {:error, error_message} ->
        {:error, {:schema_decoding_error, error_message}}
    end
  end

  @doc """
  Load schema from registry, inject metadata schema, parse into AvroEx schema

  Memoized with permament caching.
  """
  defmemo parsed_schema(message_name) do
    with {:ok, schema_name} <- if_partial_schema(message_name),
         {:ok, %{"schema" => raw_schema}} <- get(schema_name) do
      AvroEx.parse_schema(raw_schema)
    end
  end

  defp if_partial_schema(message_name) do
    event_string = message_name |> to_string

    schema_name =
      cond do
        # defined_event?(event_string) -> event_string
        Regex.match?(~r/^query\./, event_string) ->
          String.slice(event_string, 0..8)

        Regex.match?(~r/^event\.error\./, event_string) ->
          String.slice(event_string, 0..10)

        true ->
          event_string
      end

    {:ok, schema_name}
  end

  defp encode_message_with_schema(schema, message) do
    AvroEx.encode(schema, message)
  rescue
    # avro_ex can become confused when trying to encode some schemas.
    error ->
      Logger.warn(["Could not encode schema \n\t", inspect(error)])
      {:error, :unmatching_schema}
  end

  defp decode_message_with_schema(schema, encoded) do
    AvroEx.decode(schema, encoded)
  rescue
    # avro_ex can become confused when trying to decode some schemas.
    _ ->
      {:error, :unmatching_schema}
  end

  defp atomize_keys({:ok, args}) do
    {:ok, Map.Helpers.atomize_keys(args)}
  end

  defp atomize_keys(args), do: args

  @doc """
  Get schema from registry

  memoized permanetly
  """
  defmemo get(subject) do
    schema_registry_uri()
    |> Schemex.latest(subject)
  end

  def register(subject, schema) do
    schema_registry_uri()
    |> Schemex.register(subject, schema)
  end

  def register({subject, schema}), do: register(subject, schema)

  def check(subject, schema) do
    schema_registry_uri()
    |> Schemex.check(subject, schema)
  end

  def test(subject, schema) do
    schema_registry_uri()
    |> Schemex.test(subject, schema)
  end

  def subjects do
    schema_registry_uri()
    |> Schemex.subjects()
  end

  def delete(subject) do
    schema_registry_uri()
    |> Schemex.delete(subject)
  end

  defmemo defined_event?(subject) do
    case schema_registry_uri()
         |> Schemex.latest(subject) do
      {:ok, _} -> true
      _ -> false
    end
  end

  def encodable?(subject, payload) do
    {:ok, schema} = parsed_schema(subject |> to_string())
    AvroEx.encodable?(schema, payload)
  end

  defp schema_registry_uri do
    KaufmannEx.Config.schema_registry_uri()
  end

  def read_local_schema(schema_name) do
    with path <-
           Application.get_env(:kaufmann_ex, :schema_path, "priv/schemas")
           |> Path.join(schema_name <> ".avsc"),
         {:ok, file} <- File.read(path),
         {:ok, raw_schema} <- Jason.decode(file),
         {:ok, schema} <- parse_schema_with_metadata(raw_schema) do
      {:ok, schema}
    else
      err -> err
    end
  end

  def parse_schema_with_metadata(raw_schema) do
    metadata_schema =
      Application.get_env(:kaufmann_ex, :schema_path, "priv/schemas")
      |> Path.join("event_metadata.avsc")
      |> File.read!()
      |> Jason.decode!()

    [metadata_schema, raw_schema]
    |> parse()
  end

  @doc """
  AvroEx.parse without the initial json decode step
  """
  @spec parse(Enum.t(), AvroEx.Schema.Context.t()) :: {:ok, AvroEx.Schema.t()} | {:error, term}
  def parse(schema, %AvroEx.Schema.Context{} = context \\ %AvroEx.Schema.Context{}) do
    with {:ok, schema} <- AvroEx.Schema.cast(schema),
         {:ok, schema} <- AvroEx.Schema.namespace(schema),
         {:ok, context} <- AvroEx.Schema.expand(schema, context) do
      {:ok, %AvroEx.Schema{schema: schema, context: context}}
    end
  end
end
