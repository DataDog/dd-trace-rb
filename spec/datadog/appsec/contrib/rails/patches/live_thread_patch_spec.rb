# frozen_string_literal: true

require "datadog/appsec/spec_helper"
require "action_controller"
require "action_controller/metal/live"
require "action_dispatch/middleware/cookies"
require "rack/mock"
require "tempfile"
require "datadog/appsec/contrib/rails/patches/live_thread_patch"

RSpec.describe Datadog::AppSec::Contrib::Rails::Patches::LiveThreadPatch do
  before do
    allow(Datadog.logger).to receive(:warn)
    allow(Datadog::AppSec::Context).to receive(:active).and_return(context)
  end

  let(:controller) do
    live_response = response

    Class.new do
      prepend Datadog::AppSec::Contrib::Rails::Patches::LiveThreadPatch

      define_method(:response) { live_response }

      def spawn(&block)
        new_controller_thread(&block)
      end

      private

      def new_controller_thread
        Thread.new { yield }.join
      end
    end.new
  end
  let(:response) do
    ActionController::Live::Response.new.tap do |response|
      response.request = ActionDispatch::Request.new(Rack::MockRequest.env_for("/"))
    end
  end
  # NOTE: Emulates the request thread that activated the context
  let(:context) { Datadog::AppSec::Context.new(nil, nil, waf_runner).tap(&:attach) }
  let(:waf_runner) { instance_double(Datadog::AppSec::SecurityEngine::Runner, finalize!: nil) }

  context "when there is no active context" do
    before { allow(Datadog::AppSec::Context).to receive(:active).and_return(nil) }

    it "runs the block" do
      expect { |block| controller.spawn(&block) }.to yield_control
    end
  end

  context "when context is active" do
    before do
      allow(context).to receive(:attach).and_wrap_original do |method|
        attached_threads << Thread.current
        method.call
      end
    end

    let(:attached_threads) { [] }

    it "attaches inside the controller thread" do
      controller_thread = nil
      controller.spawn { controller_thread = Thread.current }

      expect(attached_threads).to eq([controller_thread])
    end

    it "keeps the context alive while the controller thread runs" do
      controller.spawn do
        context.detach

        expect(context).to be_alive
      end
    end

    it "detaches when the controller thread ends" do
      controller.spawn { nil }
      context.detach

      expect(waf_runner).to have_received(:finalize!).once
    end
  end

  context "when the block raises" do
    it "detaches" do
      expect { controller.spawn { raise "Ooops" } }.to raise_error(RuntimeError, "Ooops")
      context.detach

      expect(waf_runner).to have_received(:finalize!).once
    end
  end

  context "when context was finalized before the controller thread started" do
    before { context.detach }

    it "runs the block" do
      expect { |block| controller.spawn(&block) }.to yield_control
    end
  end

  context "when the controller thread is interrupted" do
    it "ends the work in the controller thread" do
      expect do
        controller.spawn do
          context.interrupt!({"status_code" => "403"})
          raise "unreachable"
        end
      end.not_to raise_error
    end

    it "closes the stream" do
      controller.spawn { context.interrupt!({"status_code" => "403"}) }

      expect(response.stream).to be_closed
    end
  end

  context "when the controller thread is interrupted and the stream is closed" do
    before { allow(response.stream).to receive(:close).and_call_original }

    it "does not close the stream again" do
      controller.spawn do
        response.stream.close
        context.interrupt!({"status_code" => "403"})
      end

      expect(response.stream).to have_received(:close).once
    end
  end

  context "when the controller thread is interrupted and the body is not a live stream" do
    before { response.body = file }

    after { file.close! }

    let(:file) { Tempfile.new("live_thread_patch") }

    it "does not close the body" do
      controller.spawn { context.interrupt!({"status_code" => "403"}) }

      expect(file).not_to be_closed
    end
  end

  context "when the controller thread is not interrupted" do
    it "does not close the stream" do
      controller.spawn { nil }

      expect(response.stream).not_to be_closed
    end
  end

  context "when another thread interrupted the request" do
    before { context.catch_interrupt { context.interrupt!({"status_code" => "403"}) } }

    it "does not close the stream" do
      controller.spawn { nil }

      expect(response.stream).not_to be_closed
    end
  end
end
