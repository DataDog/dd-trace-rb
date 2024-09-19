require 'datadog/tracing/contrib/propagation/sql_comment/comment'

RSpec.describe Datadog::Tracing::Contrib::Propagation::SqlComment::Comment do
  describe '#to_s' do
    [
      [
        { first_name: 'datadog', last_name: nil },
        "/*first_name='datadog'*/"
      ],
      [
        { first_name: 'data', last_name: 'dog' },
        "/*first_name='data',last_name='dog'*/"
      ],
      [
        { url_encode: 'DROP TABLE FOO' },
        "/*url_encode='DROP%20TABLE%20FOO'*/"
      ],
      [
        { route: '/polls 1000' },
        "/*route='%2Fpolls%201000'*/"
      ],
      [
        { escape_single_quote: "Dunkin' Donuts" },
        "/*escape_single_quote='Dunkin%27%20Donuts'*/"
      ],
      [
        { star: '*' },
        "/*star='%2A'*/"
      ],
      [
        { back_slash: '\\' },
        "/*back_slash='%5C'*/"
      ],
      [
        { equal_sign: '=' },
        "/*equal_sign='%3D'*/"
      ]
    ].each do |tags, comment|
      it { expect(described_class.new(tags).to_s).to eq(comment) }
    end
  end
end
