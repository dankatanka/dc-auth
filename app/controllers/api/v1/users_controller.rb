module Api
  module V1
    class UsersController < BaseController
      before_action -> { doorkeeper_authorize! :"admin:users" }

      def index
        render json: User.order(:id).map { |user| user_json(user) }
      end

      def show
        render json: user_json(User.find(params[:id]))
      end

      def create
        user = User.new(user_params)
        if user.save
          render json: user_json(user), status: :created
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_content
        end
      end

      def update
        user = User.find(params[:id])
        if user.update(user_params)
          render json: user_json(user)
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_content
        end
      end

      def destroy_tokens
        User.find(params[:id]).revoke_tokens!
        head :no_content
      end

      private

      def user_json(user)
        user.as_json(only: %i[id email first_name last_name role confirmed_at created_at updated_at])
      end

      def user_params
        params.require(:user).permit(:email, :first_name, :last_name, :role, :password, :password_confirmation)
      end
    end
  end
end
