module Admin::NavigationHelper
  def admin_nav_link_class(controller_name)
    base_classes = "px-2 py-2 rounded-md text-sm font-medium transition-colors"
    
    if admin_nav_active?(controller_name)
      "#{base_classes} bg-gray-100 text-gray-900 font-semibold"
    else
      "#{base_classes} text-gray-700 hover:text-gray-900 hover:bg-gray-50"
    end
  end

  def admin_mobile_nav_link_class(controller_name)
    base_classes = "rounded-lg px-4 py-3 text-base font-medium text-gray-700 hover:bg-gray-100"
    
    if admin_nav_active?(controller_name)
      "#{base_classes} bg-gray-100 font-semibold text-gray-900"
    else
      base_classes
    end
  end

  private

  def admin_nav_active?(controller_name)
    if controller_name == "orders"
      controller.controller_name == "orders" ||
        (controller.controller_path == "admin/sessions" && controller.action_name == "index")
    elsif controller_name == "settings"
      controller.controller_path == "admin/settings" || controller.controller_path.start_with?("admin/settings/")
    else
      controller.controller_name == controller_name
    end
  end
end
