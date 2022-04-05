class CreateTests < ActiveRecord::Migration[6.1]
  def change
    create_table :tests do |t|
      t.integer :version
      t.string :data

      t.timestamps
    end
    add_index :tests, :version
  end
end
