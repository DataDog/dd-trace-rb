class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class Article < ApplicationRecord
end

ActiveRecord::Schema.define(version: 20161003090450) do
  create_table 'articles', force: :cascade do |t|
    t.string   'title'
    t.datetime 'created_at', null: false
    t.datetime 'updated_at', null: false
  end
end

# force a SQLite access to prevent PRAGMA spans
# during tests
Article.count
