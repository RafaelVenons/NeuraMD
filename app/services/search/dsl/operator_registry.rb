module Search
  module Dsl
    class OperatorRegistry
      include ExtensionPoint
      contract :apply

      # Each handler must implement:
      #   .apply(scope, value) → ActiveRecord::Relation
      #
      # Optional:
      #   .validate(value) → nil | String (error message)

      register :tag, Operators::Tag
      register :alias, Operators::AliasOp
      register :prop, Operators::Prop
      register :kind, Operators::Kind
      register :status, Operators::Status
      register :has, Operators::Has
      register :link, Operators::Link
      register :linkedfrom, Operators::LinkedFrom
      register :orphan, Operators::Orphan
      register :deadend, Operators::Deadend
      register :created, Operators::Created
      register :updated, Operators::Updated
    end
  end
end
