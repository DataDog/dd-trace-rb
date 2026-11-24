require "datadog/tracing/contrib/support/spec_helper"
require "datadog/tracing/contrib/active_job/data_streams"
require_relative "support/helper"

RSpec.describe "Sidekiq Data Streams" do
  include_context "Sidekiq testing"

  let(:pathway_key) { Datadog::DataStreams::Processor::PROPAGATION_KEY }
  let(:data_streams_enabled) { true }
  let(:running_jid_key) { Datadog::Tracing::Contrib::Sidekiq::DataStreams::RUNNING_JID_KEY }

  let!(:orders_worker) do
    stub_const(
      "OrdersWorker",
      Class.new do
        include Sidekiq::Worker
        sidekiq_options queue: "orders"

        class << self
          attr_accessor :observed
        end

        def perform(id)
          in_context = Datadog::DataStreams.pathway_context
          self.class.observed = {in_hash: in_context.hash, in_parent_hash: in_context.parent_hash}
          NotifyWorker.perform_async(id)
          out_context = Datadog::DataStreams.pathway_context
          self.class.observed.merge!(out_hash: out_context.hash, out_parent_hash: out_context.parent_hash)
        end
      end,
    )
  end

  let!(:notify_worker) do
    stub_const(
      "NotifyWorker",
      Class.new do
        include Sidekiq::Worker
        sidekiq_options queue: "notify"

        def perform(_id)
        end
      end,
    )
  end

  let!(:failing_worker) do
    stub_const(
      "FailingWorker",
      Class.new do
        include Sidekiq::Worker

        def perform
          raise ArgumentError, "job failed"
        end
      end,
    )
  end

  before do
    skip_if_libdatadog_not_supported

    Datadog.configure do |c|
      c.tracing.instrument :sidekiq
      c.data_streams.enabled = data_streams_enabled
    end

    Sidekiq.configure_client do |config|
      config.client_middleware.clear
      config.client_middleware do |chain|
        chain.add(Datadog::Tracing::Contrib::Sidekiq::ClientTracer)
      end
    end

    Sidekiq::Testing.server_middleware.clear
    Sidekiq::Testing.server_middleware do |chain|
      chain.add(Datadog::Tracing::Contrib::Sidekiq::ServerTracer)
    end

    Sidekiq::Testing.fake!
    Sidekiq::Worker.clear_all
    Datadog::DataStreams.pathway_context = nil
    Thread.current[running_jid_key] = nil
  end

  after do
    Sidekiq::Worker.clear_all
    Datadog::DataStreams.pathway_context = nil
    Thread.current[running_jid_key] = nil
  end

  def decode(job)
    Datadog::DataStreams::PathwayContext.decode_b64(job.fetch(pathway_key))
  end

  def in_fresh_thread(&block)
    Thread.new(&block).join
  end

  describe "pushing a job" do
    it "sets a produce checkpoint on the job's queue and carries the context in the payload" do
      allow(Datadog::DataStreams).to receive(:set_produce_checkpoint).and_call_original

      in_fresh_thread { OrdersWorker.perform_async("1") }

      expect(Datadog::DataStreams).to have_received(:set_produce_checkpoint)
        .with(type: "sidekiq", destination: "orders", auto_instrumentation: true)
      expect(decode(OrdersWorker.jobs.first).hash).to be > 0
    end

    it "carries a context in every job of a bulk push" do
      in_fresh_thread { NotifyWorker.perform_bulk([["a"], ["b"], ["c"]]) }

      expect(NotifyWorker.jobs.size).to eq(3)
      expect(NotifyWorker.jobs.map { |job| decode(job).hash }.uniq.size).to eq(1)
    end

    it "keeps the original context when a stored payload is pushed again from a thread without a pathway" do
      in_fresh_thread { OrdersWorker.perform_async("1") }
      stored = OrdersWorker.jobs.first.dup
      Sidekiq::Worker.clear_all
      allow(Datadog::DataStreams).to receive(:set_produce_checkpoint).and_call_original

      in_fresh_thread { Sidekiq::Client.push(stored) }

      expect(Datadog::DataStreams).not_to have_received(:set_produce_checkpoint)
      expect(OrdersWorker.jobs.first[pathway_key]).to eq(stored[pathway_key])
    end

    it "keeps the original context when the running job pushes itself again" do
      in_fresh_thread { OrdersWorker.perform_async("1") }
      stored = OrdersWorker.jobs.first.dup
      Sidekiq::Worker.clear_all

      in_fresh_thread do
        Datadog::DataStreams.set_consume_checkpoint(type: "sidekiq", source: "orders")
        Thread.current[running_jid_key] = stored["jid"]
        Sidekiq::Client.push(stored)
      end

      expect(OrdersWorker.jobs.first[pathway_key]).to eq(stored[pathway_key])
    end

    it "checkpoints a copied payload pushed by a job that holds a pathway" do
      in_fresh_thread { OrdersWorker.perform_async("1") }
      stored = OrdersWorker.jobs.first.dup
      Sidekiq::Worker.clear_all

      in_fresh_thread do
        Datadog::DataStreams.set_consume_checkpoint(type: "sidekiq", source: "upstream")
        Sidekiq::Client.push(stored.merge("jid" => "other-jid", "queue" => "notify"))
      end

      expect(Sidekiq::Queues["notify"].first[pathway_key]).not_to eq(stored[pathway_key])
    end

    context "when Data Streams is disabled" do
      let(:data_streams_enabled) { false }

      it "leaves the payload without a pathway context" do
        OrdersWorker.perform_async("1")

        expect(OrdersWorker.jobs.first).not_to have_key(pathway_key)
      end
    end
  end

  describe "running a job" do
    it "links the forwarder's checkpoints to the producer and to the next job" do
      in_fresh_thread { OrdersWorker.perform_async("1") }
      produced = decode(OrdersWorker.jobs.first)

      in_fresh_thread { OrdersWorker.drain }
      observed = OrdersWorker.observed
      forwarded = decode(NotifyWorker.jobs.first)

      expect(observed[:in_parent_hash]).to eq(produced.hash)
      expect(observed[:out_parent_hash]).to eq(observed[:in_hash])
      expect(forwarded.hash).to eq(observed[:out_hash])
    end

    it "sets a consume checkpoint on the queue the job was fetched from" do
      in_fresh_thread { NotifyWorker.perform_async("1") }
      allow(Datadog::DataStreams).to receive(:set_consume_checkpoint).and_call_original

      NotifyWorker.drain

      expect(Datadog::DataStreams).to have_received(:set_consume_checkpoint)
        .with(type: "sidekiq", source: "notify", auto_instrumentation: true)
    end

    it "restores the thread's pathway context after the job" do
      in_fresh_thread { NotifyWorker.perform_async("1") }
      Datadog::DataStreams.set_produce_checkpoint(type: "test", destination: "before")
      context_before_job = Datadog::DataStreams.pathway_context

      NotifyWorker.drain

      expect(Datadog::DataStreams.pathway_context).to equal(context_before_job)
      expect(Thread.current[running_jid_key]).to be_nil
    end

    it "restores the thread's pathway context when the job raises" do
      in_fresh_thread { FailingWorker.perform_async }

      expect { FailingWorker.drain }.to raise_error(ArgumentError)

      expect(Datadog::DataStreams.pathway_context).to be_nil
    end

    it "does not restore a context that belongs to a replaced processor" do
      in_fresh_thread { NotifyWorker.perform_async("1") }
      old_processor = Datadog::DataStreams.send(:processor)
      new_processor = instance_double(Datadog::DataStreams::Processor, pathway_context: nil)
      allow(new_processor).to receive(:pathway_context=)
      allow(Datadog::DataStreams).to receive(:set_consume_checkpoint) do
        allow(Datadog::DataStreams).to receive(:processor).and_return(new_processor)
      end
      allow(Datadog::DataStreams).to receive(:processor).and_return(old_processor)

      NotifyWorker.drain

      expect(new_processor).not_to have_received(:pathway_context=)
    end

    it "runs the job when the consume checkpoint fails" do
      in_fresh_thread { NotifyWorker.perform_async("1") }
      allow(Datadog::DataStreams).to receive(:set_consume_checkpoint).and_raise(StandardError, "dsm failure")

      expect { NotifyWorker.drain }.not_to raise_error
    end

    context "when Data Streams is disabled" do
      let(:data_streams_enabled) { false }

      it "runs the job without a consume checkpoint" do
        NotifyWorker.perform_async("1")
        allow(Datadog::DataStreams).to receive(:set_consume_checkpoint)

        NotifyWorker.drain

        expect(Datadog::DataStreams).not_to have_received(:set_consume_checkpoint)
      end
    end
  end

  describe "jobs wrapped by ActiveJob" do
    let(:wrapped_job) { {"class" => "Sidekiq::ActiveJob::Wrapper", "wrapped" => "AuditJob", "queue" => "audit", "args" => [{}]} }

    before do
      allow(Datadog::DataStreams).to receive(:set_produce_checkpoint).and_call_original
      allow(Datadog::DataStreams).to receive(:set_consume_checkpoint).and_call_original
    end

    context "when ActiveJob Data Streams support is active" do
      before do
        stub_const("ActiveJob::Base", Class.new { prepend Datadog::Tracing::Contrib::ActiveJob::DataStreams })
      end

      it "leaves the checkpoints to ActiveJob" do
        job = wrapped_job.dup
        Datadog::Tracing::Contrib::Sidekiq::DataStreams.produce(job)
        Datadog::Tracing::Contrib::Sidekiq::DataStreams.consume(job, "audit") {}

        expect(job).not_to have_key(pathway_key)
        expect(Datadog::DataStreams).not_to have_received(:set_produce_checkpoint)
        expect(Datadog::DataStreams).not_to have_received(:set_consume_checkpoint)
      end
    end

    context "when ActiveJob Data Streams support is not active" do
      before { stub_const("ActiveJob::Base", Class.new) }

      it "checkpoints the job as a sidekiq job" do
        job = wrapped_job.dup
        in_fresh_thread { Datadog::Tracing::Contrib::Sidekiq::DataStreams.produce(job) }
        Datadog::Tracing::Contrib::Sidekiq::DataStreams.consume(job, "audit") {}

        expect(job).to have_key(pathway_key)
        expect(Datadog::DataStreams).to have_received(:set_consume_checkpoint)
          .with(type: "sidekiq", source: "audit", auto_instrumentation: true)
      end
    end
  end
end
