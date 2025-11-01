class BakeDayService
  def self.can_order_for?(date)
    bake_day = BakeDay.find_by(baked_on: date)
    return false unless bake_day

    Time.current < bake_day.cut_off_at
  end

  def self.next_available_bake_day
    BakeDay.future.ordered.first
  end

  def self.calculate_cut_off_for(date)
    BakeDay.calculate_cut_off_for(date)
  end
end

