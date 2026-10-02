module Api
  module V1
    class ApplicationsController < BaseController
      before_action -> { doorkeeper_authorize! :"admin:apps" }

      def index
        render json: Doorkeeper::Application.order(:id).map { |application| application_json(application) }
      end

      def create
        application = Doorkeeper::Application.new(application_params)
        if application.save
          render json: application_json(application).merge(secret: application.secret), status: :created
        else
          render json: { errors: application.errors.full_messages }, status: :unprocessable_content
        end
      end

      def destroy
        Doorkeeper::Application.find(params[:id]).destroy!
        head :no_content
      end

      private

      # Doorkeeper's #as_json strips scopes and uid from a confidential client.
      def application_json(application)
        application.attributes.slice("id", "name", "uid", "scopes", "redirect_uri", "confidential", "created_at")
      end

      def application_params
        params.require(:application).permit(:name, :redirect_uri, :scopes)
      end
    end
  end
end
