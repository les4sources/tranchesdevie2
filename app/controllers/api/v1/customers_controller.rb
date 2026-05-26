# frozen_string_literal: true

module Api
  module V1
    class CustomersController < BaseController
      def index
        render_collection(Customer.includes(:groups, :wallet).order(:id), CustomerSerializer)
      end

      def show
        customer = Customer.includes(:groups, :wallet).find(params[:id])
        render_resource(customer, CustomerSerializer)
      end
    end
  end
end
