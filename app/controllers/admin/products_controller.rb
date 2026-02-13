class Admin::ProductsController < Admin::BaseController
  before_action :set_product, only: [:show, :edit, :update, :destroy]
  before_action :set_product_variant, only: [:show_variant, :edit_variant, :update_variant, :destroy_variant, :reorder_variant_images]

  def index
    @products = Product.not_deleted.includes(product_variants: [ { variant_ingredients: :ingredient }, :restricted_groups ]).ordered
  end

  def show
    @variants = @product.product_variants.order(:name)
    @product_images = @product.product_images.includes(:image_attachment)
  end

  def new
    @product = Product.new
  end

  def create
    @product = Product.new(product_params)

    if @product.save
      redirect_to admin_product_path(@product), notice: 'Produit créé'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @variants = @product.product_variants.order(:name)
  end

  def update
    if @product.update(product_params)
      redirect_to admin_product_path(@product), notice: 'Produit mis à jour'
    else
      @variants = @product.product_variants.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @product.soft_delete!
    redirect_to admin_products_path, notice: 'Produit supprimé'
  end

  def new_variant
    @product = Product.find(params[:product_id])
    @variant = @product.product_variants.build
  end

  def create_variant
    @product = Product.find(params[:product_id])
    @variant = @product.product_variants.build(variant_params)

    if @variant.save
      redirect_to admin_product_path(@product), notice: 'Variante créée'
    else
      render :new_variant, status: :unprocessable_entity
    end
  end

  def show_variant
  end

  def edit_variant
    @product = @variant.product
    @variant.product_images.load # Ensure images are loaded and ordered
  end

  def update_variant
    @product = @variant.product
    if @variant.update(variant_params)
      redirect_to admin_product_path(@product), notice: 'Variante mise à jour'
    else
      render :edit_variant, status: :unprocessable_entity
    end
  end

  def destroy_variant
    @variant.destroy
    redirect_to admin_product_path(@variant.product), notice: 'Variante supprimée'
  end

  def reorder_variant_images
    @variant = ProductVariant.find(params[:variant_id])
    @product = @variant.product
    
    image_positions = params[:image_positions] || []
    
    image_positions.each_with_index do |image_id, index|
      image = @variant.product_images.find_by(id: image_id)
      image&.update_column(:position, index + 1)
    end
    
    head :ok
  end

  private

  def set_product
    @product = Product.find(params[:id])
  end

  def set_product_variant
    @variant = ProductVariant.find(params[:variant_id])
  end

  def product_params
    params.require(:product).permit(:name, :short_name, :description, :category, :position, :active, :flour, :channel)
  end

  def variant_params
    params.require(:product_variant).permit(
      :name, :price_euros, :active, :flour_quantity, :channel,
      product_images_attributes: [:id, :image, :_destroy, :position],
      variant_ingredients_attributes: [:id, :ingredient_id, :quantity, :_destroy],
      group_ids: []
    )
  end
end

