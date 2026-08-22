# frozen_string_literal: true

class AddMarketDayToBakeDays < ActiveRecord::Migration[8.0]
  def change
    add_column :bake_days, :market_day, :boolean, default: false, null: false
  end
end
