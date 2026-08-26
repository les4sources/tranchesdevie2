require 'rails_helper'

RSpec.describe SlackNotifiable do
  let(:job_class) do
    Class.new(ApplicationJob) do
      include SlackNotifiable

      def self.name
        "TestSlackNotifiableJob"
      end

      cattr_accessor :raise_error, :summary_text

      def perform
        raise StandardError, "boom" if self.class.raise_error
      end

      private

      def slack_notification_summary
        self.class.summary_text
      end
    end
  end

  before do
    stub_const("TestSlackNotifiableJob", job_class)
    job_class.raise_error = false
    job_class.summary_text = nil
  end

  context "when the job succeeds" do
    it "posts a success notification with the summary" do
      job_class.summary_text = "• 3 commandes traitées"

      expect(SlackService).to receive(:send_message) do |text|
        expect(text).to include(":white_check_mark:")
        expect(text).to include("TestSlackNotifiableJob")
        expect(text).to include("OK en")
        expect(text).to include("• 3 commandes traitées")
      end

      job_class.perform_now
    end

    it "posts a success notification without a summary line when summary is nil" do
      expect(SlackService).to receive(:send_message) do |text|
        expect(text).to include(":white_check_mark:")
        expect(text).not_to include("\n")
      end

      job_class.perform_now
    end
  end

  context "when the job raises" do
    before { job_class.raise_error = true }

    it "posts an error notification and re-raises" do
      expect(SlackService).to receive(:send_message) do |text|
        expect(text).to include(":x:")
        expect(text).to include("TestSlackNotifiableJob")
        expect(text).to include("StandardError")
        expect(text).to include("boom")
      end

      expect { job_class.perform_now }.to raise_error(StandardError, "boom")
    end
  end

  context "when Slack itself fails" do
    it "swallows the Slack error so the job result is unchanged" do
      allow(SlackService).to receive(:send_message).and_raise(SlackService::Error, "webhook down")
      expect(Rails.logger).to receive(:warn).with(/Slack notification failed/)

      expect { job_class.perform_now }.not_to raise_error
    end
  end
end
