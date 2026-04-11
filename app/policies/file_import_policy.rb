# frozen_string_literal: true

class FileImportPolicy < ApplicationPolicy
  def confirm?
    user.present?
  end

  def retry?
    user.present?
  end
end
