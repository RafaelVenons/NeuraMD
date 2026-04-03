class CanvasDocumentPolicy < ApplicationPolicy
  def bulk_update?
    user.present?
  end
end
