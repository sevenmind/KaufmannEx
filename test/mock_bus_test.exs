defmodule KaufmannEx.TestSupport.MockBusTest.ExamplePublisher do
  @moduledoc false
  def publish(event_name, payload, context \\ %{}) do
    message_body = %{
      payload: payload,
      meta: event_metadata(event_name, context)
    }

    KaufmannEx.Publisher.publish(event_name, message_body, context)
  end

  def event_metadata(event_name, context) do
    %{
      message_id: Nanoid.generate(),
      emitter_service: KaufmannEx.Config.service_name(),
      emitter_service_id: KaufmannEx.Config.service_id(),
      callback_id: context[:callback_id],
      callback_topic: nil,
      message_name: event_name |> to_string,
      timestamp: DateTime.to_string(DateTime.utc_now())
    }
  end
end


defmodule KaufmannEx.TestSupport.MockBusTest do
  @moduledoc false
  use KaufmannEx.TestSupport.MockBus
  alias KaufmannEx.TestSupport.MockSchemaRegistry
  alias KaufmannEx.TestSupport.MockBusTest.ExamplePublisher

  defmodule ExampleEventHandler do
    @moduledoc false
    use KaufmannEx.EventHandler

    def given_event(%KaufmannEx.Schemas.Event{payload: "no_event"} = event) do
      {:noreply, []}
    end

    def given_event(%KaufmannEx.Schemas.Event{payload: pl} = event) do
      {:reply, {:"test.event.publish", pl}}
    end

    def given_event(error_event), do: []
  end

  setup do
    # SERVICE_NAME and HOST_NAME must be set
    System.put_env("SERVICE_NAME", System.get_env("SERVICE_NAME") || Nanoid.generate())
    System.put_env("HOST_NAME", System.get_env("HOST_NAME") || Nanoid.generate())

    # event_handler_mod must be set
    Application.put_env(:kaufmann_ex, :event_handler_mod, ExampleEventHandler)
    Application.put_env(:kaufmann_ex, :metadata_mod, ExamplePublisher)
    Application.put_env(:kaufmann_ex, :schema_path, "test/support")

    :ok
  end

  describe "when given_event" do
    test "emits an event & payload" do
      given_event(:"test.event.publish", "Hello")

      then_event(:"test.event.publish", "Hello")
    end

    test "will raise execption if no schema" do
      message_name = :NOSCHEMA

      assert_raise ExUnit.AssertionError,
                   "\n\nSchema NOSCHEMA not registered, Is the schema in test/support?\n",
                   fn ->
                     given_event(message_name, "Some kinda payload")
                   end
    end

    test "validates payload" do
      assert_raise ExUnit.AssertionError, fn ->
        given_event(:"test.event.publish", %{invalid_key: "unexpected value"})
      end
    end

    test "sends with :default topic of no topic passed" do
      given_event(:"test.event.publish", "Hello")
      then_event(:"test.event.publish", "Hello")
    end
  end

  describe "then_event" do
    test "/1 returns payload & metadata" do
      given_event(:"test.event.publish", "Hello")

      assert %{meta: meta, payload: "Hello"} = then_event(:"test.event.publish")
    end

    test "/2 can assert a payload" do
      given_event(:"test.event.publish", "Hello")

      then_event(:"test.event.publish", "Hello")
    end

    test "/2 asserts then_event payload matches argument" do
      given_event(:"test.event.publish", "Hello")

      try do
        then_event(:"test.event.publish", "Bye")
      rescue
        error in [ExUnit.AssertionError] ->
          "Assertion with == failed" = error.message
          "Hello" = error.left
          "Bye" = error.right
      end
    end

    test "/1 returns default topic" do
      given_event(:"test.event.publish", "Test")
      assert %{topic: :default} = then_event(:"test.event.publish")
    end
  end

  describe "then_no_event" do
    test "/1 validates that event is never emitted" do
      given_event(:"test.event.publish", "no_event")
      then_no_event(:"test.event.publish")

      given_event(:"test.event.publish", "any_event")

      try do
        then_no_event(:"test.event.publish")
      rescue
        error in [ExUnit.AssertionError] ->
          "Unexpected test.event.publish recieved" = error.message
      end
    end

    test "/0 validates no events are ever emitted" do
      given_event(:"test.event.publish", "no_event")
      then_no_event()

      given_event(:"test.event.publish", "any_event")

      try do
        then_no_event()
      rescue
        error in [ExUnit.AssertionError] ->
          "No events expected" = error.message
      end
    end
  end

  describe "mock_schema_registry" do
    test "loads schemas from multiple directories" do
      Application.put_env(:kaufmann_ex, :schema_path, ["priv/schemas", "test/support"])

      assert MockSchemaRegistry.defined_event?("test.event.publish")

      assert %{} = MockSchemaRegistry.fetch_event_schema("test.event.publish")
    end
  end
end
