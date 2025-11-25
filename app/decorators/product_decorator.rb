class ProductDecorator < Draper::Decorator
  delegate_all

  CHANNEL_LABELS = {
    'store' => 'Vente en ligne',
    'admin' => 'Administrateurs uniquement'
  }.freeze

  def channel_label
    CHANNEL_LABELS[channel] || channel
  end
end

