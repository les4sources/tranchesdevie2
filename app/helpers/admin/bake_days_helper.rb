module Admin::BakeDaysHelper
  def variant_image_attachment(variant)
    variant_image = variant.product_images.find { |image| image.image.attached? }
    product_image = variant.product.product_images.find { |image| image.image.attached? }

    variant_image&.image || product_image&.image
  end

  def status_pill_classes(status)
    {
      "pending" => "bg-yellow-100 text-yellow-800",
      "unpaid" => "bg-orange-100 text-orange-800",
      "paid" => "bg-blue-100 text-blue-800",
      "ready" => "bg-emerald-100 text-emerald-800",
      "picked_up" => "bg-gray-100 text-gray-800",
      "no_show" => "bg-red-100 text-red-800",
      "cancelled" => "bg-red-100 text-red-800"
    }[status.to_s] || "bg-gray-100 text-gray-800"
  end
end


