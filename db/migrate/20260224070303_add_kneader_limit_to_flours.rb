# frozen_string_literal: true

class AddKneaderLimitToFlours < ActiveRecord::Migration[8.0]
  def change
    add_column :flours, :kneader_limit_grams, :integer
  end
end
