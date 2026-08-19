class CreateRecordShares < ActiveRecord::Migration[7.1]
  def change
    create_table :record_shares do |t|
      t.references :account, null: false
      t.string :shareable_type, null: false
      t.bigint :shareable_id, null: false
      t.string :shared_with_type, null: false
      t.bigint :shared_with_id, null: false
      t.integer :access_level, null: false, default: 0
      t.bigint :shared_by_id, null: false

      t.timestamps
    end

    add_index :record_shares, %i[shareable_type shareable_id]
    add_index :record_shares, %i[shared_with_type shared_with_id]
    add_index :record_shares, %i[shareable_type shareable_id shared_with_type shared_with_id],
              unique: true, name: 'idx_unique_record_share'
  end
end
