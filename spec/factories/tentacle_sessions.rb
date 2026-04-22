FactoryBot.define do
  factory :tentacle_session do
    association :note, factory: :note, strategy: :create
    tentacle_note_id { note.id }
    sequence(:dtach_socket) { |n| "/run/nm-tentacles/test-#{n}.sock" }
    pid_file { dtach_socket.sub(/\.sock\z/, ".pid") }
    pid { 12_345 }
    command { "bash -l" }
    cwd { "/home/rafael/apps/NeuraMD" }
    started_at { Time.current }
    status { "alive" }
    metadata { {} }

    trait :exited do
      status { "exited" }
      ended_at { Time.current }
      exit_reason { "graceful" }
      exit_code { 0 }
    end

    trait :unknown do
      status { "unknown" }
      last_seen_at { 5.minutes.ago }
    end
  end
end
