module Search
  module Dsl
    class DateParser
      RELATIVE_PATTERN = /\A([><])(\d+)([dmwy])\z/
      ABSOLUTE_PATTERN = /\A([><])(\d{4}(?:-\d{2})?(?:-\d{2})?)\z/

      Result = Data.define(:comparator, :timestamp)

      def self.call(value)
        new(value).call
      end

      def initialize(value)
        @value = value.to_s.strip
      end

      def call
        parse_relative || parse_absolute
      end

      private

      attr_reader :value

      def parse_relative
        match = value.match(RELATIVE_PATTERN)
        return unless match

        comparator = match[1] == ">" ? :gt : :lt
        amount = match[2].to_i
        unit = match[3]

        duration = case unit
        when "d" then amount.days
        when "w" then amount.weeks
        when "m" then amount.months
        when "y" then amount.years
        end

        Result.new(comparator: comparator, timestamp: duration.ago)
      end

      def parse_absolute
        match = value.match(ABSOLUTE_PATTERN)
        return unless match

        comparator = match[1] == ">" ? :gt : :lt
        date_str = match[2]

        timestamp = case date_str.length
        when 7  then Date.strptime(date_str, "%Y-%m").beginning_of_month.beginning_of_day
        when 10 then Date.strptime(date_str, "%Y-%m-%d").beginning_of_day
        when 4  then Date.strptime(date_str, "%Y").beginning_of_year.beginning_of_day
        else return nil
        end

        Result.new(comparator: comparator, timestamp: timestamp.to_time)
      rescue Date::Error
        nil
      end
    end
  end
end
