class FlagsController < ApplicationController
  layout 'admin'

  def index
    @bake_day = BakeDay.find_by(baked_on: Date.current) 
    
    if @bake_day
      @dashboard = Admin::BakeDayDashboard.new(@bake_day)
    else
      @dashboard = nil
    end
  end
end
