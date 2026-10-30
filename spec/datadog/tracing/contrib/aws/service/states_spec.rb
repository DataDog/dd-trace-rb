# frozen_string_literal: true

require "datadog/tracing/contrib/aws/service/states"

RSpec.describe Datadog::Tracing::Contrib::Aws::Service::States do
  let(:span) { instance_double("Span") }
  let(:params) { {} }
  let(:step_functions) { described_class.new }
  let(:ext) { Datadog::Tracing::Contrib::Aws::Ext }

  before do
    allow(span).to receive(:set_tag)
  end

  context "with execution_arn provided" do
    let(:execution_arn) { "arn:aws:states:us-east-1:123456789012:execution:example-state-machine:example-execution" }
    let(:params) { {execution_arn: execution_arn} }

    it "sets the state_machine_name based on the execution_arn" do
      step_functions.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_STATE_MACHINE_NAME, "example-state-machine")
    end

    it "sets the aws.execution.arn tag" do
      step_functions.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_EXECUTION_ARN, execution_arn)
    end

    it "does not claim a state machine ARN it was not given" do
      step_functions.add_tags(span, params)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_STATE_MACHINE_ARN, anything)
    end
  end

  context "with state_machine_arn provided" do
    let(:state_machine_arn) { "arn:aws:states:us-east-1:123456789012:stateMachine:MyStateMachine" }
    let(:params) { {state_machine_arn: state_machine_arn} }

    it "sets the state_machine_name based on the state_machine_arn" do
      step_functions.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_STATE_MACHINE_NAME, "MyStateMachine")
    end

    it "sets the state_machine_account_id based on the state_machine_arn" do
      step_functions.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
    end

    it "sets the aws.state_machine.arn tag" do
      step_functions.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_STATE_MACHINE_ARN, state_machine_arn)
    end

    it "does not claim an execution ARN it was not given" do
      step_functions.add_tags(span, params)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_EXECUTION_ARN, anything)
    end
  end

  context "with both execution_arn and state_machine_arn provided" do
    let(:execution_arn) { "arn:aws:states:us-east-1:987654321098:execution:example-state-machine:example-execution" }
    let(:state_machine_arn) { "arn:aws:states:us-east-1:123456789012:stateMachine:MyStateMachine" }

    it "sets the state_machine_name and state_machine_account_id based on the state_machine_arn" do
      params = {state_machine_arn: state_machine_arn}
      step_functions.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
      expect(span).to have_received(:set_tag).with(ext::TAG_STATE_MACHINE_NAME, "MyStateMachine")
    end

    it "sets the state_machine_name and state_machine_account_id based on the execution_arn" do
      params = {execution_arn: execution_arn}
      step_functions.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "987654321098")
      expect(span).to have_received(:set_tag).with(ext::TAG_STATE_MACHINE_NAME, "example-state-machine")
    end
  end

  # Both parameters describe the same state machine, so the pair is reported
  # only when they agree. A disagreement has no single target to name, and
  # emitting part of each would attribute the span to a state machine neither
  # parameter identified, so neither ARN, the account, nor the name either one
  # resolves is emitted.
  describe "with two consistent ARNs" do
    let(:execution_arn) { "arn:aws:states:us-east-1:123456789012:execution:MyStateMachine:my-execution" }
    let(:state_machine_arn) { "arn:aws:states:us-east-1:123456789012:stateMachine:MyStateMachine" }
    let(:params) { {execution_arn: execution_arn, state_machine_arn: state_machine_arn} }

    it "reports both ARNs, the shared account and the shared name" do
      step_functions.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_EXECUTION_ARN, execution_arn)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_STATE_MACHINE_ARN, state_machine_arn)
      expect(span).to have_received(:set_tag).with(ext::TAG_STATE_MACHINE_NAME, "MyStateMachine")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
    end

    context "when the execution is an Express workflow" do
      let(:execution_arn) { "arn:aws:states:us-east-1:123456789012:express:MyStateMachine:my-execution:1234-5678" }

      it "reports both ARNs, the shared account and the shared name" do
        step_functions.add_tags(span, params)
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_EXECUTION_ARN, execution_arn)
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_STATE_MACHINE_ARN, state_machine_arn)
        expect(span).to have_received(:set_tag).with(ext::TAG_STATE_MACHINE_NAME, "MyStateMachine")
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
      end
    end
  end

  describe "with two ARNs that disagree" do
    let(:state_machine_arn) { "arn:aws:states:us-east-1:123456789012:stateMachine:MyStateMachine" }
    let(:params) { {execution_arn: execution_arn, state_machine_arn: state_machine_arn} }

    shared_examples "a contradictory pair" do
      it "emits neither ARN" do
        step_functions.add_tags(span, params)
        expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_EXECUTION_ARN, anything)
        expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_STATE_MACHINE_ARN, anything)
      end

      it "emits no account" do
        step_functions.add_tags(span, params)
        expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, anything)
      end

      # Neither an ARN-derived name nor the request's own `name`. The pair
      # names no single target, and the `name` of the one operation that
      # supplies an ARN beside it is the execution's name, not the state
      # machine's.
      it "emits no name at all" do
        step_functions.add_tags(span, params)
        expect(span).not_to have_received(:set_tag).with(ext::TAG_STATE_MACHINE_NAME, anything)
      end

      it "sets no tags whatsoever" do
        step_functions.add_tags(span, params)
        expect(span).not_to have_received(:set_tag)
      end
    end

    context "on the state machine name" do
      let(:execution_arn) { "arn:aws:states:us-east-1:123456789012:execution:OtherStateMachine:my-execution" }

      it_behaves_like "a contradictory pair"
    end

    context "on the account" do
      let(:execution_arn) { "arn:aws:states:us-east-1:987654321098:execution:MyStateMachine:my-execution" }

      it_behaves_like "a contradictory pair"
    end

    context "on the Region" do
      let(:execution_arn) { "arn:aws:states:eu-west-1:123456789012:execution:MyStateMachine:my-execution" }

      it_behaves_like "a contradictory pair"
    end

    context "on the partition" do
      let(:execution_arn) { "arn:aws-us-gov:states:us-east-1:123456789012:execution:MyStateMachine:my-execution" }

      it_behaves_like "a contradictory pair"
    end

    context "on a Region one ARN omits" do
      let(:execution_arn) { "arn:aws:states::123456789012:execution:MyStateMachine:my-execution" }

      it_behaves_like "a contradictory pair"
    end

    context "on an account one ARN omits" do
      let(:execution_arn) { "arn:aws:states:us-east-1::execution:MyStateMachine:my-execution" }

      it_behaves_like "a contradictory pair"
    end

    context "on the name, with an Express execution" do
      let(:execution_arn) { "arn:aws:states:us-east-1:123456789012:express:OtherStateMachine:my-exec:1234-5678" }

      it_behaves_like "a contradictory pair"
    end

    context "when the request also carries a name" do
      let(:execution_arn) { "arn:aws:states:us-east-1:987654321098:execution:OtherStateMachine:my-execution" }
      let(:params) do
        {execution_arn: execution_arn, state_machine_arn: state_machine_arn, name: "FromRequest"}
      end

      it_behaves_like "a contradictory pair"

      it "does not fall back to the request's own name" do
        step_functions.add_tags(span, params)
        expect(span).not_to have_received(:set_tag).with(ext::TAG_STATE_MACHINE_NAME, "FromRequest")
      end
    end
  end

  # A parameter that was supplied and did not resolve leaves the request
  # naming a target this handler cannot read. Reporting the other parameter's
  # identity would be a guess about which one the caller meant, so nothing is
  # reported at all.
  describe "with one ARN that does not resolve" do
    shared_examples "an unreadable request" do
      it "sets no tags whatsoever" do
        step_functions.add_tags(span, params)
        expect(span).not_to have_received(:set_tag)
      end
    end

    context "when the execution ARN is not an ARN" do
      let(:state_machine_arn) { "arn:aws:states:us-east-1:123456789012:stateMachine:MyStateMachine" }
      let(:params) { {execution_arn: "not-an-arn", state_machine_arn: state_machine_arn} }

      it_behaves_like "an unreadable request"
    end

    context "when the state machine ARN belongs to another service" do
      let(:execution_arn) { "arn:aws:states:us-east-1:123456789012:execution:MyStateMachine:my-execution" }
      let(:params) { {execution_arn: execution_arn, state_machine_arn: "arn:aws:sns:us-east-1:123456789012:topic"} }

      it_behaves_like "an unreadable request"
    end

    context "when the state machine ARN is a Lambda ARN" do
      let(:execution_arn) { "arn:aws:states:us-east-1:123456789012:execution:MyStateMachine:my-execution" }
      let(:params) do
        {execution_arn: execution_arn, state_machine_arn: "arn:aws:lambda:us-east-1:999999999999:function:fn"}
      end

      it_behaves_like "an unreadable request"
    end
  end

  context "with an Express workflow execution_arn" do
    let(:execution_arn) do
      "arn:aws:states:us-east-1:123456789012:express:example-state-machine:example-execution:1234-5678"
    end
    let(:params) { {execution_arn: execution_arn} }

    it "resolves the state machine name and account" do
      step_functions.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_STATE_MACHINE_NAME, "example-state-machine")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_EXECUTION_ARN, execution_arn)
    end
  end

  # `name` is the state machine's own name on `CreateStateMachine`, which
  # carries no ARN. That is the only shape in which it is read.
  context "with name provided and no ARN" do
    let(:params) { {name: "MyStateMachine"} }

    it "sets the state_machine_name from the name" do
      step_functions.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_STATE_MACHINE_NAME, "MyStateMachine")
    end

    it "reports no ARNs and no account" do
      step_functions.add_tags(span, params)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_STATE_MACHINE_ARN, anything)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_EXECUTION_ARN, anything)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, anything)
    end
  end

  # `StartExecution` is the one operation that supplies a `name` beside an
  # ARN, and there the `name` is the EXECUTION's. Reporting it as
  # `statemachinename` named the wrong target, and `statemachinename` is a
  # `peer.service` source, so this is the correction that changes
  # `StartExecution`'s `peer.service`.
  describe "with a state machine ARN and an execution name" do
    context "when the ARN resolves" do
      let(:state_machine_arn) { "arn:aws:states:us-east-1:123456789012:stateMachine:MyStateMachine" }
      let(:params) { {state_machine_arn: state_machine_arn, name: "my-execution"} }

      it "reports the state machine, not the execution name" do
        step_functions.add_tags(span, params)
        expect(span).to have_received(:set_tag).with(ext::TAG_STATE_MACHINE_NAME, "MyStateMachine")
        expect(span).not_to have_received(:set_tag).with(ext::TAG_STATE_MACHINE_NAME, "my-execution")
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_STATE_MACHINE_ARN, state_machine_arn)
        expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
      end
    end

    context "when the ARN is malformed" do
      let(:params) do
        {state_machine_arn: "arn:aws:states:us-east-1:oops:stateMachine:MyStateMachine", name: "my-execution"}
      end

      it "sets no tags whatsoever, rather than naming the execution" do
        step_functions.add_tags(span, params)
        expect(span).not_to have_received(:set_tag)
      end
    end
  end

  context "with a GovCloud state_machine_arn" do
    let(:state_machine_arn) { "arn:aws-us-gov:states:us-gov-west-1:123456789012:stateMachine:MyStateMachine" }
    let(:params) { {state_machine_arn: state_machine_arn} }

    it "resolves the name, ARN and account" do
      step_functions.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_STATE_MACHINE_NAME, "MyStateMachine")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_STATE_MACHINE_ARN, state_machine_arn)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
    end
  end

  context "with a China state_machine_arn" do
    let(:state_machine_arn) { "arn:aws-cn:states:cn-north-1:123456789012:stateMachine:MyStateMachine" }
    let(:params) { {state_machine_arn: state_machine_arn} }

    it "resolves the name, ARN and account" do
      step_functions.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_STATE_MACHINE_NAME, "MyStateMachine")
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_STATE_MACHINE_ARN, state_machine_arn)
      expect(span).to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, "123456789012")
    end
  end

  context "with neither name nor ARNs provided" do
    it "sets the state_machine_name to nil" do
      step_functions.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_STATE_MACHINE_NAME, nil)
    end

    it "does not set an empty aws_account tag" do
      step_functions.add_tags(span, params)
      expect(span).not_to have_received(:set_tag).with(ext::TAG_AWS_ACCOUNT, anything)
    end
  end

  context "with malformed ARNs" do
    let(:params) do
      {
        state_machine_arn: "arn:aws:states:us-east-1:oops:stateMachine:MyStateMachine",
        execution_arn: "executionArn",
      }
    end

    it "sets no tags whatsoever" do
      step_functions.add_tags(span, params)
      expect(span).not_to have_received(:set_tag)
    end
  end

  context "with another service's ARN provided as state_machine_arn" do
    let(:params) { {state_machine_arn: "arn:aws:sns:us-east-1:123456789012:my-topic"} }

    it "sets no tags whatsoever" do
      step_functions.add_tags(span, params)
      expect(span).not_to have_received(:set_tag)
    end
  end

  # An explicit nil is not a supplied parameter, so the request is read as
  # carrying no ARN and `name` still applies.
  context "with nil ARNs and a name" do
    let(:params) { {state_machine_arn: nil, execution_arn: nil, name: "MyStateMachine"} }

    it "sets the state machine name from the name" do
      step_functions.add_tags(span, params)
      expect(span).to have_received(:set_tag).with(ext::TAG_STATE_MACHINE_NAME, "MyStateMachine")
    end
  end
end
