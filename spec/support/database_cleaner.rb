require 'database_cleaner'

RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each, :database_cleaner) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end
