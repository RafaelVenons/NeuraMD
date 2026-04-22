module Neuramd
  module Exporter
    module Collectors
      # Collector contract: implement #collect returning an Array of
      # metric descriptors (see Formatter for shape).
      class Base
        def collect
          raise NotImplementedError, "#{self.class}#collect must be implemented"
        end
      end
    end
  end
end
