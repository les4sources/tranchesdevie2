require 'rails_helper'

# ISC-55: daily job transitions paid/unpaid orders of the day to `ready` + SMS.
RSpec.describe MarkOrdersReadyJob, type: :job do
  before { allow(SlackService).to receive(:send_message) }

  let(:bake_day) { create(:bake_day, baked_on: Date.current) }

  it 'transitions a paid order to ready and sends the ready SMS' do
    order = create(:order, :paid, bake_day: bake_day)
    expect(SmsService).to receive(:send_ready).with(order)
    described_class.perform_now(Date.current)
    expect(order.reload.status).to eq('ready')
  end

  it 'does nothing when no bake day matches the date' do
    create(:order, :paid, bake_day: bake_day)
    expect(SmsService).not_to receive(:send_ready)
    described_class.perform_now(Date.current + 30)
  end
end
