module Admin::BakeDaysHelper
  def variant_image_attachment(variant)
    variant_image = variant.product_images.find { |image| image.image.attached? }
    product_image = variant.product.product_images.find { |image| image.image.attached? }

    variant_image&.image || product_image&.image
  end

  # Point de statut d'une commande dans la bulle « détail du calcul de pâte ».
  # La tonalité vient de la même table que les pastilles (`ORDER_STATUS_TONES`) :
  # une commande prête est verte au même titre dans la bulle et dans la liste.
  def dough_tooltip_dot(status)
    adm_dot(tone: Admin::UiHelper::ORDER_STATUS_TONES.fetch(status.to_s, :neutral))
  end
end
