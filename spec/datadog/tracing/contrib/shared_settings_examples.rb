RSpec.shared_examples_for 'with on_error setting' do
  context 'default without settings' do
    subject { described_class.new }

    it { expect(subject.on_error).to be_nil }
  end

  context 'when given a Proc' do
    subject { described_class.new(on_error: proc {}) }

    it { expect(subject.on_error).to be_a(Proc) }
  end

  context 'when given a object of wrong type' do
    subject { described_class.new(on_error: 1) }

    it { expect { subject }.to raise_error(ArgumentError) }
  end
end

RSpec.shared_examples_for 'with error_status_codes setting' do |env:, default:|
  context 'default without settings' do
    subject { described_class.new }

    it { expect(subject.error_status_codes).not_to include(default.min - 1) }
    it { expect(subject.error_status_codes).to include(default.min) }
    it { expect(subject.error_status_codes).to include(default.max) }
    it { expect(subject.error_status_codes).not_to include(default.max + 1) }
  end

  context 'when given error_status_codes' do
    context 'when given a single value' do
      subject { described_class.new(error_status_codes: 500) }

      it { expect(subject.error_status_codes).not_to include 400 }
      it { expect(subject.error_status_codes).not_to include 499 }
      it { expect(subject.error_status_codes).to include 500 }
      it { expect(subject.error_status_codes).not_to include 599 }
      it { expect(subject.error_status_codes).not_to include 600 }
    end

    context 'when given an array of integers' do
      subject { described_class.new(error_status_codes: [400, 500]) }

      it { expect(subject.error_status_codes).to include 400 }
      it { expect(subject.error_status_codes).not_to include 499 }
      it { expect(subject.error_status_codes).to include 500 }
      it { expect(subject.error_status_codes).not_to include 599 }
      it { expect(subject.error_status_codes).not_to include 600 }
    end

    context 'when given a range' do
      subject { described_class.new(error_status_codes: 500..600) }

      it { expect(subject.error_status_codes).not_to include 400 }
      it { expect(subject.error_status_codes).not_to include 499 }
      it { expect(subject.error_status_codes).to include 500 }
      it { expect(subject.error_status_codes).to include 599 }
      it { expect(subject.error_status_codes).to include 600 }
    end

    context 'when given an array of integer and range' do
      subject { described_class.new(error_status_codes: [400, 500..600]) }

      it { expect(subject.error_status_codes).to include 400 }
      it { expect(subject.error_status_codes).not_to include 499 }
      it { expect(subject.error_status_codes).to include 500 }
      it { expect(subject.error_status_codes).to include 599 }
      it { expect(subject.error_status_codes).to include 600 }
    end
  end

  context 'when configured with environment variable' do
    subject { described_class.new }

    context 'when given a single value' do
      around do |example|
        ClimateControl.modify(env => '500') do
          example.run
        end
      end

      it { expect(subject.error_status_codes).not_to include 400 }
      it { expect(subject.error_status_codes).not_to include 499 }
      it { expect(subject.error_status_codes).to include 500 }
      it { expect(subject.error_status_codes).not_to include 599 }
      it { expect(subject.error_status_codes).not_to include 600 }
    end

    context 'when given a comma separated list' do
      around do |example|
        ClimateControl.modify(env => '400,500') do
          example.run
        end
      end

      it { expect(subject.error_status_codes).to include 400 }
      it { expect(subject.error_status_codes).not_to include 499 }
      it { expect(subject.error_status_codes).to include 500 }
      it { expect(subject.error_status_codes).not_to include 599 }
      it { expect(subject.error_status_codes).not_to include 600 }
    end

    context 'when given a comma separated list with space' do
      around do |example|
        ClimateControl.modify(env => '400,,500') do
          example.run
        end
      end

      it { expect(subject.error_status_codes).to include 400 }
      it { expect(subject.error_status_codes).not_to include 499 }
      it { expect(subject.error_status_codes).to include 500 }
      it { expect(subject.error_status_codes).not_to include 599 }
      it { expect(subject.error_status_codes).not_to include 600 }
    end

    context 'when given a comma separated list with range' do
      around do |example|
        ClimateControl.modify(env => '400,500-600') do
          example.run
        end
      end

      it { expect(subject.error_status_codes).to include 400 }
      it { expect(subject.error_status_codes).not_to include 499 }
      it { expect(subject.error_status_codes).to include 500 }
      it { expect(subject.error_status_codes).to include 599 }
      it { expect(subject.error_status_codes).to include 600 }
    end
  end
end
