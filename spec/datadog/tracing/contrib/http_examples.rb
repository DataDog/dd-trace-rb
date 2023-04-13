RSpec.shared_examples 'with error status code configuration' do
  before { subject }

  context 'with a custom range' do
    context 'with an Range object' do
      let(:configuration_options) { { error_status_codes: 500..502 } }

      context 'with a status code within the range' do
        let(:status_code) { 501 }

        it 'marks the span as an error' do
          expect(span).to have_error
        end
      end

      context 'with a status code outside of the range' do
        let(:status_code) { 503 }

        it 'does not mark the span as an error' do
          expect(span).to_not have_error
        end
      end
    end

    context 'with an Array object' do
      let(:status_code) { 500 }

      context 'with an empty array' do
        let(:configuration_options) { { error_status_codes: [] } }

        it 'does not mark the span as an error' do
          expect(span).to_not have_error
        end
      end

      context 'with a status code in the array' do
        let(:configuration_options) { { error_status_codes: [400, 500] } }
        let(:status_code) { 400 }

        it 'marks the span as an error' do
          expect(span).to have_error
        end
      end

      context 'with a status code not in the array' do
        let(:configuration_options) { { error_status_codes: [400, 500] } }
        let(:status_code) { 401 }

        it 'does not mark the span as an error' do
          expect(span).to_not have_error
        end
      end
    end
  end

  context 'with the default range' do
    context 'with a status code lesser than the range' do
      let(:status_code) { 399 }

      it 'does not mark the span as an error' do
        expect(span).to_not have_error
      end
    end

    context 'with a status code at the beginning of the range' do
      let(:status_code) { 400 }

      it 'marks the span as an error' do
        expect(span).to have_error
      end
    end

    context 'with a status code at the end of the range' do
      let(:status_code) { 599 }

      it 'marks the span as an error' do
        expect(span).to have_error
      end
    end

    context 'with a status code greater than the range' do
      let(:status_code) { 600 }

      it 'does not mark the span as an error' do
        expect(span).to_not have_error
      end
    end
  end
end
