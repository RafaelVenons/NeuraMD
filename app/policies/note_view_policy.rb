class NoteViewPolicy < ApplicationPolicy
  def results?
    user.present?
  end

  def reorder?
    user.present?
  end
end
