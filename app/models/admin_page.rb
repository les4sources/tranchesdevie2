class AdminPage < ApplicationRecord
  validates :slug, presence: true, uniqueness: true
  validates :title, presence: true

  def to_param
    slug
  end
end

