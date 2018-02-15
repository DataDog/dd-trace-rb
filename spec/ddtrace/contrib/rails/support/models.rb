RSpec.shared_context 'Rails models' do
  let(:application_record) do
    stub_const('ApplicationRecord', Class.new(ActiveRecord::Base) do
      self.abstract_class = true
    end)
  end

  let(:models) do
    # Force connection to initialize, and dump some spans
    # TODO: Refactor this... needs it badly.
    [].tap { application_record.connection }
  end

  # TODO: Figure out how to run database migrations to setup models
  # let(:article_model) do
  #   stub_const('Article', Class.new(application_record))
  # end

  # let(:article_migration) do
  #   Proc.new do
  #     create_table 'articles', force: :cascade do |t|
  #       t.string   'title'
  #       t.datetime 'created_at', null: false
  #       t.datetime 'updated_at', null: false
  #     end
  #   end
  # end

  # let(:table_migrations) do
  #   [article_migration]
  # end

  # let(:run_database_migrations!) do
  #   # check if the migration has been executed
  #   # MySQL JDBC drivers require that, otherwise we get a
  #   # "Table '?' already exists" error
  #   begin
  #     models.each(&:count)
  #   rescue ActiveRecord::StatementInvalid
  #     logger.info 'Executing database migrations'
  #     ActiveRecord::Schema.define(version: 20161003090450) do
  #       table_migrations.each { |m| self.instance_eval(&m) }
  #     end
  #   else
  #     logger.info 'Database already exists; nothing to do'
  #   end

  #   # force an access to prevent extra spans during tests
  #   article_model.count
  # end
end