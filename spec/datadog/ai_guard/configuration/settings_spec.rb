# frozen_string_literal: true

require "datadog/ai_guard/configuration"

RSpec.describe Datadog::AIGuard::Configuration::Settings do
  subject(:settings) { Datadog::Core::Configuration::Settings.new }

  describe "ai_guard" do
    describe "#enabled" do
      context "when DD_AI_GUARD_ENABLED is not defined" do
        with_env "DD_AI_GUARD_ENABLED" => nil

        it { expect(settings.ai_guard.enabled).to be(false) }
      end

      context "when DD_AI_GUARD_ENABLED is defined as true" do
        with_env "DD_AI_GUARD_ENABLED" => "true"

        it { expect(settings.ai_guard.enabled).to be(true) }
      end

      context "when DD_AI_GUARD_ENABLED is defined as false" do
        with_env "DD_AI_GUARD_ENABLED" => "false"

        it { expect(settings.ai_guard.enabled).to be(false) }
      end
    end

    describe "#enabled=" do
      context "when set to true" do
        before { settings.ai_guard.enabled = true }

        it { expect(settings.ai_guard.enabled).to be(true) }
      end

      context "when set to false" do
        before { settings.ai_guard.enabled = false }

        it { expect(settings.ai_guard.enabled).to be(false) }
      end
    end

    describe "#endpoint" do
      context "when DD_AI_GUARD_ENDPOINT is not defined" do
        with_env "DD_AI_GUARD_ENDPOINT" => nil

        it { expect(settings.ai_guard.endpoint).to be_nil }
      end

      context "when DD_AI_GUARD_ENDPOINT is defined" do
        with_env "DD_AI_GUARD_ENDPOINT" => "https://ap.datadoghq.com/api/v2/ai-guard"

        it { expect(settings.ai_guard.endpoint).to eq("https://ap.datadoghq.com/api/v2/ai-guard") }
      end
    end

    describe "#endpoint=" do
      it "changes endpoint value" do
        expect { settings.ai_guard.endpoint = "https://app.datad0g.com/api/v2/ai-guard" }
          .to change { settings.ai_guard.endpoint }.to("https://app.datad0g.com/api/v2/ai-guard")
      end

      it "removes '/' suffix" do
        expect { settings.ai_guard.endpoint = "https://app.datad0g.com/api/v2/ai-guard/" }
          .to change { settings.ai_guard.endpoint }.to("https://app.datad0g.com/api/v2/ai-guard")
      end

      it "raises when a relative URI is provided" do
        expect { settings.ai_guard.endpoint = "/api/v2/ai-guard" }.to raise_error(
          ArgumentError, "Please provide an absolute URI that includes a protocol"
        )
      end

      it "raises when a URI without a protocol is provided" do
        expect { settings.ai_guard.endpoint = "app.datadog.com/api/v2/ai-guard" }.to raise_error(
          ArgumentError, "Please provide an absolute URI that includes a protocol"
        )
      end
    end

    describe "#app_key" do
      context "when DD_APP_KEY is not defined" do
        with_env "DD_APP_KEY" => nil

        it { expect(settings.ai_guard.app_key).to be nil }

        context "when DD_APP_KEY is defined" do
          with_env "DD_APP_KEY" => "some-app-key"

          it { expect(settings.ai_guard.app_key).to eq("some-app-key") }
        end
      end
    end

    describe "#app_key=" do
      it "changes app key value" do
        expect { settings.ai_guard.app_key = 'new-app-key' }
          .to change { settings.ai_guard.app_key }.to('new-app-key')
      end
    end

    describe "#timeout_ms" do
      context "when DD_AI_GUARD_TIMEOUT is not defined" do
        with_env "DD_AI_GUARD_TIMEOUT" => nil

        it { expect(settings.ai_guard.timeout_ms).to eq(10_000) }
      end

      context "when DD_AI_GUARD_TIMEOUT is defined" do
        with_env "DD_AI_GUARD_TIMEOUT" => "20000"

        it { expect(settings.ai_guard.timeout_ms).to eq(20_000) }
      end
    end

    describe "#timeout_ms=" do
      it "changes timeout value" do
        expect { settings.ai_guard.timeout_ms = 30_000 }
          .to change { settings.ai_guard.timeout_ms }.to(30_000)
      end
    end

    describe "#max_content_size_bytes" do
      context "when DD_AI_GUARD_MAX_CONTENT_SIZE is not defined" do
        with_env "DD_AI_GUARD_MAX_CONTENT_SIZE" => nil

        it { expect(settings.ai_guard.max_content_size_bytes).to eq(512 * 1024) }
      end

      context "when DD_AI_GUARD_MAX_CONTENT_SIZE is defined" do
        with_env "DD_AI_GUARD_MAX_CONTENT_SIZE" => "262144"

        it { expect(settings.ai_guard.max_content_size_bytes).to eq(262_144) }
      end
    end

    describe "#max_content_size_bytes=" do
      it "changes max_content_size_bytes value" do
        expect { settings.ai_guard.max_content_size_bytes = 1024 * 1024 }
          .to change { settings.ai_guard.max_content_size_bytes }.to(1024 * 1024)
      end
    end

    describe "#max_messages_length" do
      context "when DD_AI_GUARD_MAX_MESSAGES_LENGTH is not defined" do
        with_env "DD_AI_GUARD_MAX_MESSAGES_LENGTH" => nil

        it { expect(settings.ai_guard.max_messages_length).to eq(16) }
      end

      context "when DD_AI_GUARD_MAX_MESSAGES_LENGTH is defined" do
        with_env "DD_AI_GUARD_MAX_MESSAGES_LENGTH" => "32"

        it { expect(settings.ai_guard.max_messages_length).to eq(32) }
      end
    end

    describe "#max_messages_length=" do
      it "changes max_messages_length value" do
        expect { settings.ai_guard.max_messages_length = 24 }
          .to change { settings.ai_guard.max_messages_length }.to(24)
      end
    end
  end
end
