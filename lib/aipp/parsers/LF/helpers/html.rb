module AIPP
  module Helpers
    module HTML

      def cleanup!
        html.css('del').each { |n| n.remove }   # remove deleted entries
      end

    end
  end
end