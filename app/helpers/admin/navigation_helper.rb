module Admin::NavigationHelper
  def admin_nav_link_class(controller_name)
    base_classes = "px-2 py-2 rounded-md text-sm font-medium transition-colors"
    
    # Check if current controller matches, or if we're on admin root (sessions#index) and it's orders
    is_active = if controller_name == "orders"
                  controller.controller_name == "orders" ||
                    (controller.controller_path == "admin/sessions" && controller.action_name == "index")
                else
                  controller.controller_name == controller_name
                end
    
    if is_active
      "#{base_classes} bg-gray-100 text-gray-900 font-semibold"
    else
      "#{base_classes} text-gray-700 hover:text-gray-900 hover:bg-gray-50"
    end
  end
end
