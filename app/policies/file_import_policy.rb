# frozen_string_literal: true

class FileImportPolicy < ApplicationPolicy
  def retry?
    user.present?
  end
end
