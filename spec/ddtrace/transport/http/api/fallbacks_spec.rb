require 'spec_helper'

require 'ddtrace/transport/http/api/fallbacks'

RSpec.describe Datadog::Transport::HTTP::API::Fallbacks do
  context 'when implemented' do
    subject(:test_object) { test_class.new }

    let(:test_class) { Class.new { include Datadog::Transport::HTTP::API::Fallbacks } }

    describe '#fallbacks' do
      subject(:fallbacks) { test_object.fallbacks }

      it { is_expected.to eq({}) }
    end

    describe '#with_fallbacks' do
      subject(:with_fallbacks) { test_object.with_fallbacks(fallbacks) }

      let(:existing_fallbacks) { { V2: :V1 } }

      before do
        allow(test_object).to receive(:fallbacks).and_return(existing_fallbacks)
      end

      context 'when the fallbacks' do
        context 'overlap with existing fallbacks' do
          let(:fallbacks) { { V2: :V0 } }

          it do
            is_expected.to be test_object
            expect(test_object.fallbacks).to eq(V2: :V0)
          end
        end

        context 'do not intersect with existing fallbacks' do
          let(:fallbacks) { { V3: :V2 } }

          it do
            is_expected.to be test_object
            expect(test_object.fallbacks).to include(V3: :V2, V2: :V1)
          end
        end
      end
    end

    describe '#add_fallbacks!' do
      subject(:add_fallbacks!) { test_object.add_fallbacks!(fallbacks) }

      let(:existing_fallbacks) { { V2: :V1 } }

      before do
        allow(test_object).to receive(:fallbacks).and_return(existing_fallbacks)
      end

      context 'when the fallbacks' do
        context 'overlap with existing fallbacks' do
          let(:fallbacks) { { V2: :V0 } }

          it do
            is_expected.to be test_object.fallbacks
            expect(test_object.fallbacks).to eq(V2: :V0)
          end
        end

        context 'do not intersect with existing fallbacks' do
          let(:fallbacks) { { V3: :V2 } }

          it do
            is_expected.to be test_object.fallbacks
            expect(test_object.fallbacks).to include(V3: :V2, V2: :V1)
          end
        end
      end
    end
  end
end
