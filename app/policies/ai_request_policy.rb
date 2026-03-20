class AiRequestPolicy < ApplicationPolicy
  def retry? = update?

  class Scope < Scope
    def resolve
      user.present? ? scope.all : scope.none
    end
  end
end
