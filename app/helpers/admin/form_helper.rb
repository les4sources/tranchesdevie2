# frozen_string_literal: true

module Admin::FormHelper
  # Shared input styling for admin form fields (text, password, email, etc.)
  # Provides proper padding, border, and focus states
  def admin_input_class(extra = "")
    base = "block w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 shadow-sm " \
           "focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500 focus:outline-none"
    [ base, extra ].compact.join(" ").strip
  end

  # Options du <select> de cible d'une remise ciblée : un optgroup par produit,
  # avec « Tout le produit » puis chaque variante. Valeurs "product_<id>" /
  # "variant_<id>" (cf. GroupProductDiscount#target=).
  def group_discount_target_options(products, selected = nil)
    grouped = products.map do |product|
      options = [ [ "Tout le produit", "product_#{product.id}" ] ]
      product.product_variants.each do |variant|
        options << [ "— #{variant.name}", "variant_#{variant.id}" ]
      end
      [ product.name, options ]
    end
    grouped_options_for_select(grouped, selected)
  end
end
