class ProductVariantDecorator < Draper::Decorator
  delegate_all

  CHANNEL_LABELS = {
    "store" => "Vente en ligne",
    "admin" => "Boulangers uniquement"
  }.freeze

  def channel_label
    CHANNEL_LABELS[channel] || channel
  end

  # Libellé court de la restriction par jour de cuisson, ou nil si la variante
  # est disponible tous les jours. Ex. "Mardi uniquement", "Mardi et vendredi".
  def weekday_restriction_label
    return nil unless restricted_to_weekdays?

    names = available_weekdays.sort.map { |wday| BakeDay::WDAY_LABELS[wday] }.compact
    return nil if names.empty?

    label = names.size == 1 ? "#{names.first} uniquement" : names.to_sentence(two_words_connector: " et ", last_word_connector: " et ")
    label.capitalize
  end
end
