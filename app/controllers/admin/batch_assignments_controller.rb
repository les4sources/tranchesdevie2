class Admin::BatchAssignmentsController < Admin::BaseController
  include Admin::BatchPlannerRendering

  before_action :set_bake_day

  # Affecte des lignes à une fournée — ou les désaffecte quand `batch_id` est
  # vide. Trois portées, volontairement combinables (#194) : une ligne, tout un
  # client, toute une variante — plus les pains d'une Camembert Party. Affecter une variante puis retirer un client
  # précis doit rester possible, donc la dernière action gagne, sans mémoire.
  #
  # Rien n'est proposé ni deviné : la répartition est manuelle de bout en bout.
  def update
    items = scoped_items

    if items.empty?
      return render_planner(notice: "Aucune ligne à affecter.")
    end

    # Les pains de Camembert Party sont calculés, sans ligne enregistrée :
    # leur fournée s'écrit sur l'événement (#camembert-parties).
    breads, lines = items.partition(&:camembert_bread?)
    OrderItem.where(id: lines.map(&:id)).update_all(batch_id: target_batch&.id, updated_at: Time.current) if lines.any?
    if breads.any?
      PartyEvent.where(id: breads.map { |item| item.camembert_party_event.id })
                .update_all(bread_batch_id: target_batch&.id, updated_at: Time.current)
    end

    render_planner(notice: assignment_notice(items.size))
  end

  private

  # Portée de l'affectation, toujours restreinte aux lignes que CE jour de
  # cuisson produit — on ne peut pas affecter la ligne d'un autre jour.
  def scoped_items
    items = Admin::BakeDayDashboard.new(@bake_day).production_items

    if params[:order_item_id].present?
      id = params[:order_item_id].to_i
      items.select { |item| item.id == id }
    elsif params[:party_event_id].present?
      id = params[:party_event_id].to_i
      items.select { |item| item.camembert_party_event&.id == id }
    elsif params[:customer_id].present?
      # Les pains de Camembert Party pendent à la commande d'un inscrit, mais
      # n'appartiennent pas à ce client : ils ont leur propre groupe.
      id = params[:customer_id].to_i
      orders = Order.where(id: items.map(&:order_id), customer_id: id).pluck(:id).to_set
      items.select { |item| !item.camembert_bread? && orders.include?(item.order_id) }
    elsif params[:product_variant_id].present?
      id = params[:product_variant_id].to_i
      items.select { |item| item.product_variant_id == id }
    else
      []
    end
  end

  def target_batch
    return nil if params[:batch_id].blank?

    @target_batch ||= @bake_day.batches.find(params[:batch_id])
  end

  def assignment_notice(count)
    lines = "#{count} ligne#{'s' if count > 1}"

    if target_batch
      "#{lines} → #{target_batch.name}."
    else
      "#{lines} remise#{'s' if count > 1} en non affectées."
    end
  end
end
