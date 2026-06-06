require 'rails_helper'

RSpec.describe FetchStripeFeeJob, type: :job do
  it 'delegates fee retrieval to StripeFeeService' do
    payment = create(:payment)
    expect(StripeFeeService).to receive(:fetch_for).with(payment)

    described_class.perform_now(payment)
  end
end
