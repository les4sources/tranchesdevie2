require 'rails_helper'

# ISC-56: post-cut-off job delegates each eligible bake day to the (already-tested)
# ProcessPlannedOrdersService. Here we verify the job's selection logic.
RSpec.describe ProcessPlannedOrdersJob, type: :job do
  before { allow(SlackService).to receive(:send_message) }

  it 'processes a past-cut-off bake day that still has planned orders' do
    bake_day = create(:bake_day, :cut_off_passed)
    create(:order, :planned, bake_day: bake_day)
    expect(ProcessPlannedOrdersService).to receive(:process_for_bake_day).with(bake_day)
    described_class.perform_now
  end

  it 'skips a past-cut-off bake day with no planned orders' do
    create(:bake_day, :cut_off_passed)
    expect(ProcessPlannedOrdersService).not_to receive(:process_for_bake_day)
    described_class.perform_now
  end
end
