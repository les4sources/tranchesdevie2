class Admin::GroupsController < Admin::BaseController
  before_action :set_group, only: [ :edit, :update ]
  before_action :load_products, only: [ :new, :create, :edit, :update ]

  def index
    @groups = Group.order(created_at: :desc)
  end

  def new
    @group = Group.new
  end

  def create
    @group = Group.new(group_params)

    if @group.save
      redirect_to admin_groups_path, notice: "Groupe créé avec succès"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @group.update(group_params)
      redirect_to admin_groups_path, notice: "Groupe mis à jour avec succès"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_group
    @group = Group.find(params[:id])
  end

  def load_products
    @products = Product.not_deleted.ordered.includes(:product_variants)
  end

  def group_params
    params.require(:group).permit(
      :name, :discount_percent,
      group_product_discounts_attributes: [ :id, :target, :discount_kind, :discount_value_raw, :_destroy ]
    )
  end
end
