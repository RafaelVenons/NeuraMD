class AiRequestPolicy < ApplicationPolicy
  def retry? = update?
  def resolve_queue? = show?

  class Scope < Scope
    def resolve
      user.present? ? scope.all : scope.none
    end
  end
end
