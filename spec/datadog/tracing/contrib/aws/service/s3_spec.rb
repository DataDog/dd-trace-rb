# frozen_string_literal: true

require "aws-sdk"
require "datadog/tracing/contrib/aws/parsed_context"
require "datadog/tracing/contrib/aws/service/s3"

RSpec.describe Datadog::Tracing::Contrib::Aws::Service::S3 do
  let(:span) { instance_double("Span") }
  let(:params) { {} }
  let(:s3) { described_class.new }

  before do
    allow(span).to receive(:set_tag)
  end

  context "with bucket name provided" do
    let(:params) { {bucket: "my-bucket-name"} }

    it "sets the bucket_name based on the provided bucket name" do
      s3.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_BUCKET_NAME, "my-bucket-name")
    end
  end

  context "with no bucket name provided" do
    it "sets the bucket_name to nil" do
      s3.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(Datadog::Tracing::Contrib::Aws::Ext::TAG_BUCKET_NAME, nil)
    end
  end

  describe "#add_owner_tags" do
    subject(:add_owner_tags) { s3.add_owner_tags(span, params, context) }

    let(:context) { instance_double(Datadog::Tracing::Contrib::Aws::ParsedContext) }
    let(:status_code) { 200 }
    let(:host) { "my-bucket-name.s3.us-east-1.amazonaws.com" }
    let(:params) { {bucket: "my-bucket-name", expected_bucket_owner: "123456789012"} }

    before do
      allow(context).to receive(:safely).with(:status_code).and_return(status_code)
      allow(context).to receive(:safely).with(:host).and_return(host)
    end

    context "when the response succeeded" do
      it "sets the aws_account tag" do
        add_owner_tags
        expect(span).to have_received(:set_tag)
          .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, "123456789012")
      end
    end

    # The full status and endpoint matrix lives with the shared gate, in the
    # spec for `Service::Base#aws_confirmed_response?`. These three cover that
    # S3 actually applies it.
    context "when the bucket owner does not match" do
      let(:status_code) { 403 }

      it "does not set the aws_account tag" do
        add_owner_tags
        expect(span).not_to have_received(:set_tag)
          .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, anything)
      end
    end

    context "when the request failed for an unrelated reason" do
      let(:status_code) { 500 }

      it "does not set the aws_account tag" do
        add_owner_tags
        expect(span).not_to have_received(:set_tag)
          .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, anything)
      end
    end

    context "when an S3-compatible endpoint answers 2xx" do
      let(:host) { "minio.internal" }

      it "does not set the aws_account tag" do
        add_owner_tags
        expect(span).not_to have_received(:set_tag)
          .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, anything)
      end
    end

    context "with no expected_bucket_owner" do
      let(:params) { {bucket: "my-bucket-name"} }

      it "does not set the aws_account tag" do
        add_owner_tags
        expect(span).not_to have_received(:set_tag)
          .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, anything)
      end
    end

    context "with a malformed expected_bucket_owner" do
      ["", "1234", "1234567890123", "12345678901a", "123456789012 ", "1234-5678-9012"].each do |malformed|
        context "of #{malformed.inspect}" do
          let(:params) { {bucket: "my-bucket-name", expected_bucket_owner: malformed} }

          it "does not set the aws_account tag" do
            add_owner_tags
            expect(span).not_to have_received(:set_tag)
              .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, anything)
          end
        end
      end
    end

    context "with only expected_source_bucket_owner" do
      let(:params) { {bucket: "my-bucket-name", expected_source_bucket_owner: "123456789012"} }

      it "does not set the aws_account tag" do
        add_owner_tags
        expect(span).not_to have_received(:set_tag)
          .with(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, anything)
      end
    end
  end
end
