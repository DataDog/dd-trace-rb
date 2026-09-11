# frozen_string_literal: true

require "datadog/appsec/spec_helper"
require "datadog/appsec/contrib/aws_lambda/tagging"

RSpec.describe Datadog::AppSec::Contrib::AwsLambda::Tagging do
  let(:span) do
    instance_double(Datadog::Tracing::SpanOperation, set_tag: nil, set_metric: nil, get_tag: nil)
  end
  let(:trace) { instance_double(Datadog::Tracing::TraceOperation, keep!: nil, set_tag: nil) }
  let(:context) do
    instance_double(
      Datadog::AppSec::Context,
      span: span,
      trace: trace,
      waf_runner_ruleset_version: "1.12.0",
      waf_runner_known_addresses: ["server.request.headers.no_cookies"],
    )
  end

  before do
    stub_const("Datadog::AppSec::WAF::VERSION::BASE_STRING", "1.30.0")
    allow(Datadog::AppSec::DefaultHeaderTags).to receive_messages(tag_request: nil, tag_response: nil)
    allow(Datadog::Tracing::ClientIp).to receive(:set_client_ip_tag!)
  end

  it "tags request headers and client IP" do
    request = instance_double(
      Datadog::AppSec::Contrib::AwsLambda::Request,
      headers: {"user-agent" => "TestBot"},
      remote_addr: "192.0.2.1",
    )

    described_class.tag_request(request, context: context)

    expect(Datadog::AppSec::DefaultHeaderTags).to have_received(:tag_request).with(
      span,
      kind_of(Datadog::Core::HeaderCollection),
    )
    expect(Datadog::Tracing::ClientIp).to have_received(:set_client_ip_tag!).with(
      span,
      headers: kind_of(Datadog::Core::HeaderCollection),
      remote_ip: "192.0.2.1",
    )
  end

  it "tags response headers and derives content length" do
    response = instance_double(
      Datadog::AppSec::Contrib::AwsLambda::Response,
      headers: {"content-type" => "text/plain"},
      body: "hello",
    )

    described_class.tag_response(response, context: context)

    expect(Datadog::AppSec::DefaultHeaderTags).to have_received(:tag_response).with(
      span,
      kind_of(Datadog::Core::HeaderCollection),
    )
    expect(span).to have_received(:set_tag).with("http.response.headers.content-length", "5")
  end

  it "adds AppSec runtime metadata without keeping warm-start traces" do
    described_class.tag_and_keep(context, cold_start: false)

    expect(span).to have_received(:set_metric).with(Datadog::AppSec::Ext::TAG_APPSEC_ENABLED, 1)
    expect(span).to have_received(:set_tag).with("_dd.runtime_family", "ruby")
    expect(span).to have_received(:set_tag).with("_dd.appsec.event_rules.version", "1.12.0")
    expect(trace).not_to have_received(:keep!)
  end

  it "keeps cold-start AppSec traces and records WAF addresses" do
    described_class.tag_and_keep(context, cold_start: true)

    expect(trace).to have_received(:keep!)
    expect(trace).to have_received(:set_tag).with(
      Datadog::Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER,
      Datadog::Tracing::Sampling::Ext::Decision::ASM,
    )
    expect(span).to have_received(:set_tag).with(
      "_dd.appsec.event_rules.addresses",
      '["server.request.headers.no_cookies"]',
    )
  end
end
