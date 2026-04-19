module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      user_id = cookies.encrypted[Rails.application.config.session_options[:key]]&.dig("warden.user.user.key", 0, 0)
      user_id ||= env["warden"]&.user&.id
      user = User.find_by(id: user_id) if user_id
      user || reject_unauthorized_connection
    end
  end
end
