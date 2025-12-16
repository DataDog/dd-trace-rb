# frozen_string_literal: true

require "datadog/ai_guard/api_client"

RSpec.describe Datadog::AIGuard::APIClient do
  describe "#post" do
    let(:api_client) do
      described_class.new(
        endpoint: "/api/v2/ai-guard",
        api_key: "api-key",
        application_key: "application-key",
        timeout: 10000
      )
    end

    let(:response_body) do
      {
        some: "response"
      }
    end

    subject(:post) { api_client.post("/evaluate", body: {}) }

    before do
      WebMock.enable!

      stub_request(:post, "https://app.datadoghq.com/api/v2/ai-guard/evaluate")
        .with(headers: {
          "DD-API-KEY": "api-key",
          "DD-APPLICATION-KEY": "application-key",
          "DD-AI-GUARD-VERSION": Datadog::VERSION::STRING,
          "DD-AI-GUARD-SOURCE": "SDK",
          "DD-AI-GUARD-LANGUAGE": "ruby",
          "content-type": "application/json"
        })
        .to_return do |request|
          {
            status: response_status_code,
            body: response_body.to_json,
            headers: {"Content-Type" => "application/json"}
          }
        end
    end

    after do
      WebMock.reset!
      WebMock.disable!
    end

    context "when response is success" do
      let(:response_status_code) { 200 }

      it "returns a parsed response body" do
        expect(post).to eq("some" => "response")
      end
    end

    context "when response is 301 Moved Permanently" do
      let(:response_status_code) { 301 }

      it "raises Datadog::AIGuard::APIClient::NotFoundError" do
        expect { post }.to raise_error(
          Datadog::AIGuard::APIClient::UnexpectedRedirectError, "Redirects for AI Guard API are not supported"
        )
      end
    end

    context "when response is 404 Not Found" do
      let(:response_status_code) { 404 }

      it "raises Datadog::AIGuard::APIClient::NotFoundError" do
        expect { post }.to raise_error(Datadog::AIGuard::APIClient::NotFoundError)
      end
    end

    context "when response is 429 Too Many Requests" do
      let(:response_status_code) { 429 }

      it "raises Datadog::AIGuard::APIClient::TooManyRequestsError" do
        expect { post }.to raise_error(Datadog::AIGuard::APIClient::TooManyRequestsError)
      end
    end

    context "when response is 401 Unauthorized" do
      let(:response_status_code) { 401 }

      it "raises Datadog::AIGuard::APIClient::UnauthorizedError" do
        expect { post }.to raise_error(Datadog::AIGuard::APIClient::UnauthorizedError)
      end
    end

    context "when response is 401 Forbidden" do
      let(:response_status_code) { 403 }

      it "raises Datadog::AIGuard::APIClient::ForbiddenError" do
        expect { post }.to raise_error(Datadog::AIGuard::APIClient::ForbiddenError)
      end
    end

    context "when response is some other 4xx" do
      let(:response_status_code) { 422 }

      it "raises Datadog::AIGuard::APIClient::ClientError" do
        expect { post }.to raise_error(Datadog::AIGuard::APIClient::ClientError)
      end
    end

    context "when response is 500 Server Error" do
      let(:response_status_code) { 500 }

      it "raises Datadog::AIGuard::APIClient::ServerError" do
        expect { post }.to raise_error(Datadog::AIGuard::APIClient::ServerError)
      end
    end

    context "when response is some unexpected code" do
      let(:response_status_code) { 100 }

      it "raises Datadog::AIGuard::APIClient::UnexpectedResponseError" do
        expect { post }.to raise_error(Datadog::AIGuard::APIClient::UnexpectedResponseError)
      end
    end

    context "when read timeout occurs" do
      before do
        stub_request(:post, "https://app.datadoghq.com/api/v2/ai-guard/evaluate").to_raise(Net::ReadTimeout)
      end

      it "raises Datadog::AIGuard::APIClient::ReadTimeout" do
        expect { post }.to raise_error(Datadog::AIGuard::APIClient::ReadTimeout)
      end
    end
  end
end
