require "rails_helper"

RSpec.describe NoteViewPolicy do
  let(:user) { create(:user) }
  let(:view) { create(:note_view) }

  subject { described_class.new(user, view) }

  %i[index? show? create? update? destroy? results? reorder?].each do |action|
    it "permits #{action} for signed-in user" do
      expect(subject.public_send(action)).to be true
    end
  end

  it "denies all for nil user" do
    policy = described_class.new(nil, view)
    expect(policy.show?).to be false
  end
end
