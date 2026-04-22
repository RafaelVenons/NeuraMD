module Neuramd
  module Exporter
    # Formats metric descriptors into Prometheus text format 0.0.4.
    # Descriptor shape:
    #   {
    #     name: "neuramd_foo_total",
    #     type: "counter",      # counter | gauge
    #     help: "Human text.",
    #     samples: [
    #       { value: 42 },                          # no labels
    #       { labels: { outcome: "ok" }, value: 7 } # with labels
    #     ]
    #   }
    module Formatter
      CONTENT_TYPE = "text/plain; version=0.0.4; charset=utf-8".freeze

      def self.format(metrics)
        lines = []
        metrics.each do |metric|
          next unless metric && metric[:name]
          lines << "# HELP #{metric[:name]} #{escape_help(metric[:help].to_s)}"
          lines << "# TYPE #{metric[:name]} #{metric[:type] || "untyped"}"
          samples = metric[:samples] || []
          if samples.empty?
            # emit zero sample so the series is visible in Prometheus
            lines << "#{metric[:name]} 0"
          else
            samples.each do |sample|
              lines << "#{metric[:name]}#{format_labels(sample[:labels])} #{format_value(sample[:value])}"
            end
          end
        end
        "#{lines.join("\n")}\n"
      end

      def self.format_labels(labels)
        return "" if labels.nil? || labels.empty?
        parts = labels.sort_by { |k, _| k.to_s }.map do |k, v|
          %{#{k}="#{escape_label_value(v.to_s)}"}
        end
        "{#{parts.join(",")}}"
      end

      def self.format_value(value)
        return "NaN" if value.nil?
        float = value.to_f
        float.finite? ? float.to_s : (float.nan? ? "NaN" : (float > 0 ? "+Inf" : "-Inf"))
      end

      def self.escape_label_value(value)
        value.to_s.gsub("\\", "\\\\\\\\").gsub('"', '\\"').gsub("\n", "\\n")
      end

      def self.escape_help(value)
        value.gsub("\\", "\\\\\\\\").gsub("\n", "\\n")
      end
    end
  end
end
