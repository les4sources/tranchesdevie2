# frozen_string_literal: true

module Admin::FormHelper
  # Shared input styling for admin form fields (text, password, email, etc.)
  # Provides proper padding, border, and focus states
  def admin_input_class(extra = "")
    base = "block w-full rounded-md border border-gray-300 px-3 py-2 text-sm text-gray-900 shadow-sm " \
           "focus:border-indigo-500 focus:ring-1 focus:ring-indigo-500 focus:outline-none"
    [base, extra].compact.join(" ").strip
  end
end
