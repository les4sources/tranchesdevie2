# frozen_string_literal: true

# Proposition de répartition du jour en fournées (calculateur #194) : le bouton
# « Proposer une répartition ». Les règles vivent dans `BatchPacker` ; ici, on
# pèse les produits du jour, on range les pâtons, et on écrit les fournées.
#
# La répartition reste MANUELLE par défaut (décision boulangers du 25/08/2026) :
# ce service ne tourne que sur clic, et les boulangers corrigent ensuite ligne à
# ligne comme avant.
class BatchProposalService
  # 70 kg de pain par fournée, jours de marché compris (Claire, 28/09/2026). Les
  # pâtons n'y comptent pas : ils ne cuisent pas dans le four à pain.
  CAPACITY_GRAMS = 70_000
  # Taille maximale d'un produit qu'on glisse dans la fournée d'une autre farine.
  SMALL_PRODUCT_GRAMS = 10_000

  # Rang de passage d'une farine (règle 3). Les farines hors de la liste de
  # Claire, comme le blé ancien, passent entre le seigle et le froment.
  FROMENT_RANK = 4

  def self.flour_rank(flour)
    return 3 if flour.nil?

    name = I18n.transliterate(flour.name).downcase
    if name.include?("petit epeautre") then 0
    elsif name.include?("epeautre") then 1
    elsif name.include?("seigle") then 2
    elsif name.include?("froment") then FROMENT_RANK
    else 3
    end
  end

  # Farine principale d'un produit : celle qui pèse le plus dans sa recette.
  def self.main_flour(product)
    product.product_flours.max_by { |product_flour| [ product_flour.percentage, -flour_rank(product_flour.flour) ] }&.flour
  end

  attr_reader :bake_day, :dashboard

  def initialize(bake_day, dashboard = Admin::BakeDayDashboard.new(bake_day))
    @bake_day = bake_day
    @dashboard = dashboard
  end

  # Les fournées proposées, dans l'ordre, chacune un Array d'`OrderItem`. Ne
  # touche pas la base.
  def proposal
    @proposal ||= begin
      items = dashboard.production_items.sort_by(&:id)
      breads, others = items.partition { |item| item.product_variant.product.breads? }
      by_id = items.index_by(&:id)

      groups = BatchPacker.new(packer_products(breads), capacity: CAPACITY_GRAMS, small_product_grams: SMALL_PRODUCT_GRAMS)
                          .call
                          .map { |ids| by_id.values_at(*ids) }

      attach_patons(groups, others)
    end
  end

  # Remplace les fournées du jour par la proposition. Renvoie le nombre de
  # fournées créées ; sans aucune ligne à répartir, ne touche à rien.
  def apply!
    groups = proposal
    return 0 if groups.empty?

    Batch.transaction do
      bake_day.batches.destroy_all
      groups.each.with_index(1) do |items, position|
        batch = bake_day.batches.create!(name: "Fournée #{position}", position: position)
        OrderItem.where(id: items.map(&:id)).update_all(batch_id: batch.id, updated_at: Time.current)
      end
    end

    groups.size
  end

  private

  def packer_products(items)
    items.group_by { |item| item.product_variant.product }
         .sort_by { |product, _| [ self.class.flour_rank(self.class.main_flour(product)), product.name.downcase ] }
         .map do |product, product_items|
           flour = self.class.main_flour(product)

           BatchPacker::Product.new(
             key: product.id,
             family: flour&.id || :none,
             rank: self.class.flour_rank(flour),
             ingredients: product_items.flat_map { |item| item.product_variant.variant_ingredients.map(&:ingredient_id) }.to_set,
             lines: product_items.map { |item| [ item.id, item.qty * (item.product_variant.flour_quantity || 0) ] }
           )
         end
  end

  # Les pâtons (et tout ce qui n'est pas du pain) rejoignent la première
  # fournée froment : ils sont pétris avec elle, mais ne comptent pas dans ses
  # 70 kg puisqu'ils cuisent au four à bois. Sans fournée froment, la dernière.
  def attach_patons(groups, others)
    return groups if others.empty?
    return [ others ] if groups.empty?

    target = groups.index { |items| items.any? { |item| froment?(item) } } || groups.size - 1
    groups[target] += others
    groups
  end

  def froment?(item)
    self.class.flour_rank(self.class.main_flour(item.product_variant.product)) == FROMENT_RANK
  end
end
