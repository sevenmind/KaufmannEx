defmodule KaufmannEx.TestSupport.MockSchemaRegistryTest do
  use ExUnit.Case

  alias KaufmannEx.Publisher.Request
  alias KaufmannEx.TestSupport.MockBus
  alias KaufmannEx.TestSupport.MockSchemaRegistry

  setup do
    Application.put_env(:kaufmann_ex, :schema_path, "test/support")

    Application.put_env(
      :kaufmann_ex,
      :transcoder,
      default: KaufmannEx.TestSupport.Transcoder.SevenAvro,
      json: KaufmannEx.Transcoder.Json
    )

    :ok
  end

  describe "defined_event?" do
    test "when defined" do
      assert MockSchemaRegistry.defined_event?("test.event.publish")
    end

    test "when not defined" do
      refute MockSchemaRegistry.defined_event?("This Event Does not Exist")
    end
  end

  describe "encodable?/2" do
    test "when valid schema" do
      assert MockSchemaRegistry.encodable?(%Request{
               event_name: "test.event.publish",
               payload: "Hello",
               metadata: MockBus.fake_meta("test.event.publish")
             })
    end
  end
end
