require "spec_helper"
require "datadog/tracing/contrib/waterdrop/middleware"

RSpec.describe "Data Streams Monitoring remote configuration" do
  before { skip_if_libdatadog_not_supported }

  let(:env_value) { nil }
  let(:remote) { Datadog::Tracing::Remote }

  around do |example|
    ClimateControl.modify("DD_DATA_STREAMS_ENABLED" => env_value) { example.run }
  end

  before do
    stub_request(:post, %r{/v0.1/pipeline_stats}).to_return(status: 200, body: "")
    Datadog.configure do |c|
      c.remote.enabled = false
      c.telemetry.enabled = false
      c.agent.host = "localhost"
      c.agent.port = 9999
    end
  end

  after { Datadog.shutdown! }

  def processor
    Datadog.send(:components).data_streams
  end

  # Delivers one APM_TRACING config; `lib_config: nil` delivers none (RC key removed).
  def apply_rc(lib_config)
    contents = []
    unless lib_config.nil?
      contents << Datadog::Core::Remote::Configuration::Content.parse(
        path: "datadog/1/APM_TRACING/anything/lib_config",
        content: JSON.dump({"lib_config" => lib_config}),
      )
    end
    remote.merge_and_apply_configs(instance_double(Datadog::Core::Remote::Configuration::Repository, contents: contents))
  end

  def enable_via_rc = apply_rc({"data_streams_enabled" => true})

  def disable_via_rc = apply_rc({"data_streams_enabled" => false})

  def remove_rc_key = apply_rc({})

  context "when DSM is off at startup" do
    it "starts the processor when remote config enables it" do
      expect(Datadog::DataStreams.enabled?).to be false

      enable_via_rc

      expect(Datadog::DataStreams.enabled?).to be true
      expect(processor).to be_a(Datadog::DataStreams::Processor)
      expect(processor.running?).to be true
    end

    it "keeps working checkpoints once enabled" do
      enable_via_rc

      expect(Datadog::DataStreams.set_produce_checkpoint(type: "kafka", destination: "orders")).to be_a(String)
    end

    it "does nothing when remote config does not mention data_streams_enabled" do
      apply_rc({"log_injection_enabled" => false})

      expect(Datadog::DataStreams.enabled?).to be false
    end

    it "does not create a second processor when the same value is delivered twice" do
      enable_via_rc
      first = processor

      enable_via_rc

      expect(processor).to equal(first)
    end
  end

  context "when DSM is on at startup" do
    let(:env_value) { "true" }

    it "stops the processor, flushes it and releases its thread when remote config disables it" do
      enable_via_rc
      running = processor
      running.set_produce_checkpoint(type: "kafka", destination: "orders")

      disable_via_rc

      expect(Datadog::DataStreams.enabled?).to be false
      expect(running.running?).to be false
      expect(a_request(:post, %r{/v0.1/pipeline_stats})).to have_been_made
    end

    it "falls back to the environment value when the remote config key is removed" do
      disable_via_rc
      expect(Datadog::DataStreams.enabled?).to be false

      remove_rc_key

      expect(Datadog::DataStreams.enabled?).to be true
    end
  end

  context "when DSM is off in the environment" do
    let(:env_value) { "false" }

    it "falls back to disabled when the remote config key is removed" do
      enable_via_rc
      expect(Datadog::DataStreams.enabled?).to be true

      remove_rc_key

      expect(Datadog::DataStreams.enabled?).to be false
    end
  end

  describe "environment variable and remote config precedence" do
    [
      # env,    rc,    expected
      [nil, nil, false],
      [nil, true, true],
      [nil, false, false],
      ["true", nil, true],
      ["true", true, true],
      ["true", false, false],
      ["false", nil, false],
      ["false", true, true],
      ["false", false, false],
    ].each do |env, rc, expected|
      context "with DD_DATA_STREAMS_ENABLED=#{env.inspect} and remote config #{rc.inspect}" do
        let(:env_value) { env }

        it "resolves to #{expected}" do
          apply_rc(rc.nil? ? {} : {"data_streams_enabled" => rc})

          expect(Datadog::DataStreams.enabled?).to be expected
        end
      end
    end
  end

  describe "re-enabling after a disable" do
    it "builds a fresh running processor each cycle" do
      enable_via_rc
      first = processor
      disable_via_rc
      expect(first.running?).to be false

      enable_via_rc

      expect(processor).not_to equal(first)
      expect(processor.running?).to be true
    end

    it "keeps recording checkpoints after the cycle" do
      3.times do
        enable_via_rc
        expect(Datadog::DataStreams.set_produce_checkpoint(type: "kafka", destination: "orders")).to be_a(String)
        disable_via_rc
        expect(Datadog::DataStreams.set_produce_checkpoint(type: "kafka", destination: "orders")).to be_nil
      end
    end
  end

  describe "when disabled" do
    it "makes the checkpoint API a no-op that leaves the carrier untouched" do
      carrier = {}
      yielded = false

      result = Datadog::DataStreams.set_produce_checkpoint(type: "kafka", destination: "orders") do |key, value|
        yielded = true
        carrier[key] = value
      end

      expect(result).to be_nil
      expect(yielded).to be false
      expect(carrier).to be_empty
    end

    it "leaves messages produced through the WaterDrop middleware untouched" do
      message = {topic: "orders", payload: "x", headers: {"a" => "b"}}

      expect(Datadog::Tracing::Contrib::WaterDrop::Middleware.call(message))
        .to eq({topic: "orders", payload: "x", headers: {"a" => "b"}})
    end
  end

  describe "robustness" do
    it "ignores non-boolean values" do
      apply_rc({"data_streams_enabled" => "yes"})

      expect(Datadog::DataStreams.enabled?).to be false
    end

    it "does not raise when the processor cannot be built" do
      allow(Datadog::DataStreams::Processor).to receive(:new).and_raise("boom")

      expect { enable_via_rc }.not_to raise_error
      expect(Datadog::DataStreams.enabled?).to be false
    end

    it "does not raise when stopping the processor fails" do
      enable_via_rc
      allow(processor).to receive(:flush).and_raise("boom")

      expect { disable_via_rc }.not_to raise_error
      expect(Datadog::DataStreams.enabled?).to be false
    end

    it "builds a single processor when many threads enable it concurrently" do
      Datadog::DataStreams.enabled? # build the components up front, as the RC worker only reuses them
      built = Queue.new
      allow(Datadog::DataStreams::Processor).to receive(:new).and_wrap_original do |original, **args|
        original.call(**args).tap { |p| built << p }
      end

      Array.new(8) { Thread.new { enable_via_rc } }.each(&:join)

      expect(built.size).to eq(1)
      expect(processor.running?).to be true
    end
  end

  describe "forking" do
    it "keeps the flush thread of a processor started by remote config running in the child" do
      skip "Fork not supported on current platform" unless Process.respond_to?(:fork)

      enable_via_rc

      expect_in_fork do
        Datadog.send(:components).after_fork

        expect(processor.running?).to be true
      end
    end
  end
end
