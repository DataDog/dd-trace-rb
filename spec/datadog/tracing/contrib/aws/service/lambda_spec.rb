# frozen_string_literal: true

require "datadog/tracing/contrib/aws/service/lambda"

RSpec.describe Datadog::Tracing::Contrib::Aws::Service::Lambda do
  let(:span) { instance_double("Span") }
  let(:params) { {} }
  let(:lambda_service) { described_class.new }
  let(:ext) { Datadog::Tracing::Contrib::Aws::Ext }

  before do
    allow(span).to receive(:set_tag)
  end

  context "with a bare function name" do
    let(:params) { {function_name: "my-function"} }

    it "sets the function name" do
      lambda_service.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my-function")
    end

    it "reports no ARN, because the request carries none" do
      lambda_service.add_tags(span, params)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_ARN, anything)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, anything)
    end
  end

  context "with a name-and-qualifier function name" do
    let(:params) { {function_name: "my-function:PROD"} }

    it "reports the function, not the alias" do
      lambda_service.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my-function")
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_ARN, anything)
    end
  end

  context "with a name-and-version function name" do
    let(:params) { {function_name: "my-function:1"} }

    it "reports the function, not the version" do
      lambda_service.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my-function")
    end
  end

  context "with a partial ARN" do
    let(:params) { {function_name: "123456789012:function:my-function"} }

    it "resolves the function name and account" do
      lambda_service.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my-function")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
    end

    it "reports no ARN, because the Region and partition are unknown" do
      lambda_service.add_tags(span, params)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_ARN, anything)
    end
  end

  context "with a qualified partial ARN" do
    let(:params) { {function_name: "123456789012:function:my-function:PROD"} }

    it "resolves the function name and account without an ARN" do
      lambda_service.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my-function")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_ARN, anything)
    end
  end

  context "with a full ARN" do
    let(:function_name) { "arn:aws:lambda:us-west-2:123456789012:function:my-function" }
    let(:params) { {function_name: function_name} }

    it "resolves the function name, ARN and account" do
      lambda_service.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my-function")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_ARN, function_name)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
    end
  end

  context "with a qualified full ARN" do
    let(:function_name) { "arn:aws:lambda:us-west-2:123456789012:function:my-function:PROD" }
    let(:params) { {function_name: function_name} }

    it "reports the name without its qualifier" do
      lambda_service.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my-function")
    end

    # The ARN tag records the exact resource the request addressed. Trimming
    # the qualifier would report the unqualified function ARN, which names a
    # different resource than the one this span called.
    it "reports the ARN byte for byte, qualifier included" do
      lambda_service.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_ARN, function_name)
      expect(span).not_to have_received(:set_tag)
        .with(ext::TAG_AWS_FUNCTION_ARN, "arn:aws:lambda:us-west-2:123456789012:function:my-function")
    end
  end

  context "with a full ARN qualified by a version number" do
    let(:function_name) { "arn:aws:lambda:us-west-2:123456789012:function:my-function:42" }
    let(:params) { {function_name: function_name} }

    it "keeps the version in the ARN and out of the name" do
      lambda_service.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my-function")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_ARN, function_name)
    end
  end

  context "with a GovCloud full ARN" do
    let(:function_name) { "arn:aws-us-gov:lambda:us-gov-west-1:123456789012:function:my-function" }
    let(:params) { {function_name: function_name} }

    it "resolves the function name, ARN and account" do
      lambda_service.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my-function")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_ARN, function_name)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
    end
  end

  context "with a China full ARN" do
    let(:function_name) { "arn:aws-cn:lambda:cn-north-1:123456789012:function:my-function" }
    let(:params) { {function_name: function_name} }

    it "resolves the function name, ARN and account" do
      lambda_service.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my-function")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_ARN, function_name)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
    end
  end

  context "with a layer ARN" do
    let(:params) { {function_name: "arn:aws:lambda:us-west-2:123456789012:layer:my-layer:1"} }

    it "claims no function identity" do
      lambda_service.add_tags(span, params)
      expect(span).not_to have_received(:set_tag)
    end
  end

  context "with another service's ARN" do
    let(:params) { {function_name: "arn:aws:sns:us-west-2:123456789012:my-topic"} }

    it "claims no function identity" do
      lambda_service.add_tags(span, params)
      expect(span).not_to have_received(:set_tag)
    end
  end

  context "with a malformed ARN" do
    let(:params) { {function_name: "arn:aws:lambda:us-west-2:oops:function:my-function"} }

    it "claims no function identity" do
      lambda_service.add_tags(span, params)
      expect(span).not_to have_received(:set_tag)
    end
  end

  context "with a truncated ARN" do
    let(:params) { {function_name: "arn:aws:lambda"} }

    it "claims no function identity" do
      lambda_service.add_tags(span, params)
      expect(span).not_to have_received(:set_tag)
    end
  end

  # A wrong-sized account prefix matches neither the partial-ARN grammar nor
  # the bare-name grammar, which accepts at most one qualifier after the name.
  # The previous handler reported the account segment as the function name.
  describe "with a wrong-sized account prefix" do
    [
      ["too few digits", "12345:function:my-function"],
      ["too many digits", "1234567890123:function:my-function"],
    ].each do |description, value|
      context "that has #{description}" do
        let(:params) { {function_name: value} }

        it "sets no tags at all" do
          lambda_service.add_tags(span, params)
          expect(span).not_to have_received(:set_tag)
        end
      end
    end
  end

  # Indistinguishable from the account id a partial ARN opens with, so it is
  # never reported as a function name.
  context "with a function_name of exactly twelve digits" do
    let(:params) { {function_name: "123456789012"} }

    it "sets no tags at all" do
      lambda_service.add_tags(span, params)
      expect(span).not_to have_received(:set_tag)
    end
  end

  context "with an account id followed by a bare qualifier" do
    let(:params) { {function_name: "123456789012:function"} }

    it "does not promote the account number to a function name" do
      lambda_service.add_tags(span, params)
      expect(span).not_to have_received(:set_tag)
    end
  end

  context "with no function_name" do
    it "sets no tags" do
      lambda_service.add_tags(span, params)
      expect(span).not_to have_received(:set_tag)
    end
  end

  context "with an empty function_name" do
    let(:params) { {function_name: ""} }

    it "sets no tags" do
      lambda_service.add_tags(span, params)
      expect(span).not_to have_received(:set_tag)
    end
  end

  context "with a colon-only function_name" do
    let(:params) { {function_name: ":"} }

    it "sets no tags" do
      lambda_service.add_tags(span, params)
      expect(span).not_to have_received(:set_tag)
    end
  end

  context "with a non-string function_name" do
    let(:params) { {function_name: 1234} }

    it "sets no tags" do
      lambda_service.add_tags(span, params)
      expect(span).not_to have_received(:set_tag)
    end
  end

  # A value shaped like a partial ARN is judged only as one. Each case below
  # would otherwise leave an account on the span with no function to attach it
  # to, or promote a fragment of the value to `aws.function.name`.
  describe "with a malformed partial ARN" do
    [
      ["no function name after the type", "123456789012:function:"],
      ["a trailing colon where the name should be", "123456789012:function::"],
      ["a name of only a qualifier separator", "123456789012:function: :"],
      ["a space in the name", "123456789012:function:my function"],
      ["a slash in the name", "123456789012:function:my/function"],
      ["an empty qualifier", "123456789012:function:my-function:"],
      ["an invalid qualifier", "123456789012:function:my-function:bad qualifier"],
      ["a dot in the qualifier", "123456789012:function:my-function:v1.0"],
      ["a segment beyond the qualifier", "123456789012:function:my-function:PROD:extra"],
      ["a name longer than 64 characters", "123456789012:function:#{"a" * 65}"],
      ["a qualifier longer than 128 characters", "123456789012:function:my-function:#{"a" * 129}"],
      ["a layer in place of the function", "123456789012:layer:my-layer"],
      ["a qualified layer in place of the function", "123456789012:layer:my-layer:1"],
    ].each do |description, malformed|
      context "that has #{description}" do
        let(:params) { {function_name: malformed} }

        it "sets no tags at all" do
          lambda_service.add_tags(span, params)
          expect(span).not_to have_received(:set_tag)
        end
      end
    end
  end

  describe "with a valid partial ARN at the boundaries" do
    context "with a 64-character name" do
      let(:name) { "a" * 64 }
      let(:params) { {function_name: "123456789012:function:#{name}"} }

      it "resolves the name and account" do
        lambda_service.add_tags(span, params)
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, name)
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
      end
    end

    context "with an underscored name" do
      let(:params) { {function_name: "123456789012:function:my_function_v2"} }

      it "resolves the name and account" do
        lambda_service.add_tags(span, params)
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my_function_v2")
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
      end
    end

    context "with a $LATEST qualifier" do
      let(:params) { {function_name: "123456789012:function:my-function:$LATEST"} }

      it "resolves the name and account without an ARN" do
        lambda_service.add_tags(span, params)
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my-function")
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
        expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_ARN, anything)
      end
    end

    context "with a numeric version qualifier" do
      let(:params) { {function_name: "123456789012:function:my-function:7"} }

      it "resolves the name and account" do
        lambda_service.add_tags(span, params)
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my-function")
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
      end
    end

    # The published pattern lets a partial ARN carry the target Region ahead
    # of the account. It still names no partition, so there is still no ARN to
    # report.
    describe "with a Region ahead of the account" do
      [
        ["a commercial Region", "us-west-2:123456789012:function:my-function"],
        ["a GovCloud Region", "us-gov-west-1:123456789012:function:my-function"],
        ["an ISO Region", "us-iso-east-1:123456789012:function:my-function"],
      ].each do |description, value|
        context "with #{description}" do
          let(:params) { {function_name: value} }

          it "resolves the name and account without an ARN" do
            lambda_service.add_tags(span, params)
            expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my-function")
            expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
            expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_ARN, anything)
          end
        end
      end
    end
  end

  # The published name class is `[a-zA-Z0-9-_\.]`, so a dot belongs to the
  # name in every form. The handler previously rejected any name carrying one.
  describe "with a dot in the function name" do
    context "in a bare name" do
      let(:params) { {function_name: "my.function.v2"} }

      it "resolves the whole dotted name" do
        lambda_service.add_tags(span, params)
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my.function.v2")
      end
    end

    context "in a qualified bare name" do
      let(:params) { {function_name: "my.function:PROD"} }

      it "resolves the dotted name without its qualifier" do
        lambda_service.add_tags(span, params)
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my.function")
      end
    end

    context "in a partial ARN" do
      let(:params) { {function_name: "123456789012:function:my.function"} }

      it "resolves the dotted name and the account" do
        lambda_service.add_tags(span, params)
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my.function")
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
      end
    end

    context "in a full ARN" do
      let(:function_name) { "arn:aws:lambda:us-west-2:123456789012:function:my.function" }
      let(:params) { {function_name: function_name} }

      it "resolves the dotted name, ARN and account" do
        lambda_service.add_tags(span, params)
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my.function")
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_ARN, function_name)
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
      end
    end
  end

  # `$LATEST.PUBLISHED` is one of the two qualifier alternatives the published
  # pattern names, alongside `$LATEST` itself. The handler previously accepted
  # only the latter.
  describe "with a $LATEST.PUBLISHED qualifier" do
    context "on a bare name" do
      let(:params) { {function_name: "my-function:$LATEST.PUBLISHED"} }

      it "resolves the function and reports no ARN" do
        lambda_service.add_tags(span, params)
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my-function")
        expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_ARN, anything)
      end
    end

    context "on a partial ARN" do
      let(:params) { {function_name: "123456789012:function:my-function:$LATEST.PUBLISHED"} }

      it "resolves the function and the account" do
        lambda_service.add_tags(span, params)
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my-function")
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
      end
    end

    context "on a full ARN" do
      let(:function_name) { "arn:aws:lambda:us-west-2:123456789012:function:my-function:$LATEST.PUBLISHED" }
      let(:params) { {function_name: function_name} }

      it "keeps the qualifier in the ARN and out of the name" do
        lambda_service.add_tags(span, params)
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "my-function")
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_ARN, function_name)
      end
    end
  end

  describe "with a bare name at the length boundaries" do
    context "with a 64-character name" do
      let(:name) { "a" * 64 }
      let(:params) { {function_name: name} }

      it "resolves the name" do
        lambda_service.add_tags(span, params)
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, name)
      end
    end

    context "with a 65-character name" do
      let(:params) { {function_name: "a" * 65} }

      it "sets no tags at all" do
        lambda_service.add_tags(span, params)
        expect(span).not_to have_received(:set_tag)
      end
    end
  end

  # The whole parameter is capped at 256 characters. The name and qualifier
  # grammars cap their own segments far more tightly, so what the overall
  # limit still catches is a partition or Region long enough to push an
  # otherwise structurally valid ARN past it.
  describe "with a full ARN at the overall length limit" do
    context "with the longest ARN the segment grammars accept" do
      let(:function_name) { "arn:aws:lambda:us-west-2:123456789012:function:#{"a" * 64}:#{"b" * 128}" }
      let(:params) { {function_name: function_name} }

      it "stays inside the limit" do
        expect(function_name.length).to be <= 256
      end

      it "resolves the function" do
        lambda_service.add_tags(span, params)
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_NAME, "a" * 64)
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_FUNCTION_ARN, function_name)
      end
    end

    context "with an overlong partition" do
      let(:function_name) { "arn:aws-#{"a" * 220}:lambda:us-west-2:123456789012:function:my-function" }
      let(:params) { {function_name: function_name} }

      it "is over the limit" do
        expect(function_name.length).to be > 256
      end

      it "sets no tags at all" do
        lambda_service.add_tags(span, params)
        expect(span).not_to have_received(:set_tag)
      end
    end
  end

  # A full ARN's resource is validated as strictly as a bare name: the literal
  # `function` type, then a name and at most one qualifier. The previous
  # handler read the second resource segment and ignored everything after it.
  describe "with a full ARN whose resource does not validate" do
    [
      ["a segment beyond the qualifier", "arn:aws:lambda:us-west-2:123456789012:function:my-fn:PROD:extra"],
      ["a space in the name", "arn:aws:lambda:us-west-2:123456789012:function:my fn"],
      ["a slash in place of the type separator", "arn:aws:lambda:us-west-2:123456789012:function/my-fn"],
      ["an empty name", "arn:aws:lambda:us-west-2:123456789012:function:"],
      ["an empty qualifier", "arn:aws:lambda:us-west-2:123456789012:function:my-fn:"],
      ["a dot in the qualifier", "arn:aws:lambda:us-west-2:123456789012:function:my-fn:v1.0"],
      ["a name longer than 64 characters", "arn:aws:lambda:us-west-2:123456789012:function:#{"a" * 65}"],
      ["an event source mapping", "arn:aws:lambda:us-west-2:123456789012:event-source-mapping:1234"],
    ].each do |description, value|
      context "that has #{description}" do
        let(:params) { {function_name: value} }

        it "sets no tags at all" do
          lambda_service.add_tags(span, params)
          expect(span).not_to have_received(:set_tag)
        end
      end
    end
  end

  # A value opening with `arn:` is judged only as a full ARN. Reading it as a
  # name would report a malformed ARN as a function called `arn`.
  context "with a value that merely opens like an ARN" do
    let(:params) { {function_name: "arn:aws"} }

    it "sets no tags at all" do
      lambda_service.add_tags(span, params)
      expect(span).not_to have_received(:set_tag)
    end
  end

  context "with a function_name whose bytes are invalid in its encoding" do
    let(:params) do
      {function_name: (+"arn:aws:lambda:us-west-2:123456789012:function:my\xFFfn").force_encoding("UTF-8")}
    end

    it "sets no tags and does not raise" do
      expect { lambda_service.add_tags(span, params) }.not_to raise_error
      expect(span).not_to have_received(:set_tag)
    end
  end

  context "with a function_name in a non ASCII-compatible encoding" do
    let(:params) { {function_name: "my-function".encode("UTF-16LE")} }

    it "sets no tags and does not raise" do
      expect { lambda_service.add_tags(span, params) }.not_to raise_error
      expect(span).not_to have_received(:set_tag)
    end
  end

  # Lambda `peer.service` is sourced from `peer.hostname`, which is what the
  # other Datadog tracers report for the same call. Adding the function name
  # to the source list would rename the same dependency differently depending
  # on which tracer observed it, so this is asserted as a decision rather than
  # left implicit.
  describe "peer.service compatibility" do
    it "keeps aws.function.name out of the peer.service sources" do
      expect(ext::PEER_SERVICE_SOURCES).not_to include(ext::TAG_AWS_FUNCTION_NAME)
      expect(ext::PEER_SERVICE_SOURCES).not_to include(ext::TAG_AWS_FUNCTION_ARN)
    end

    it "leaves peer.hostname as the only Lambda-reachable source" do
      recorded = {}
      allow(span).to receive(:set_tag) { |key, value| recorded[key] = value }

      lambda_service.add_tags(span, {function_name: "arn:aws:lambda:us-west-2:123456789012:function:my-function"})

      expect(recorded.keys & ext::PEER_SERVICE_SOURCES).to be_empty
      expect(ext::PEER_SERVICE_SOURCES).to include(Datadog::Tracing::Metadata::Ext::TAG_PEER_HOSTNAME)
    end
  end
end
