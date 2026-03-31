class PropertyDefinitionPolicy < ApplicationPolicy
  def reorder?
    user.present?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.all
    end
  end
end
