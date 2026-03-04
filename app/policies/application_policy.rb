class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index? = user.present?
  def show? = user.present?
  def create? = user.present?
  def new? = create?
  def update? = user.present?
  def edit? = update?
  def destroy? = user.present?

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      scope.all
    end

    private

    attr_reader :user, :scope
  end
end
