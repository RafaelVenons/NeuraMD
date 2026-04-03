FactoryBot.define do
  factory :canvas_document do
    sequence(:name) { |n| "Canvas #{n}" }
    viewport { {"x" => 0, "y" => 0, "zoom" => 1.0} }
    position { 0 }
  end
end
