require "rails_helper"

RSpec.describe CanvasDocumentPolicy do
  let(:user) { create(:user) }
  let(:doc) { create(:canvas_document) }

  subject { described_class.new(user, doc) }

  %i[index? show? create? update? destroy? bulk_update?].each do |action|
    it "permits #{action} for signed-in user" do
      expect(subject.public_send(action)).to be true
    end
  end

  it "denies all for nil user" do
    policy = described_class.new(nil, doc)
    expect(policy.show?).to be false
  end
end
