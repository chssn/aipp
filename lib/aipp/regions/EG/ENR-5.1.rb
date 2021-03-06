module AIPP
  module EG

    # D/P/R Zones
    class ENR51 < AIP

      include AIPP::EG::Helpers::Base

      # Map sections to whether to parse them
      SECTIONS = {
        '5.1-1':   true,
        '5.1-2':   false,
        '5.1-3':   true,
        '5.1-4':   true,
        '5.1-5-1': false,
        '5.1-5-2': true
      }

      # Map source types to type and optional local type
      SOURCE_TYPES = {
        'D' => { type: 'D' },
        'P' => { type: 'P' },
        'R' => { type: 'R' },
        'ZIT' => { type: 'P', local_type: 'ZIT' }
      }.freeze

      # Radius to use for zones consisting of one point only
      POINT_RADIUS = AIXM.d(1, :km).freeze

      def parse
        skip = false
        prepare(html: read).css('h4, thead ~ tbody').each do |tag|
          case tag.name
          when 'h4'
            section = tag.text.match(/^ENR ([\d.-]+)/).captures.first
            skip = !SECTIONS.fetch(section.to_sym)
            verbose_info "#{skip ? :Skipping : :Parsing} section #{section}"
          when 'tbody'
            next if skip
            airspace = nil
            tag.css('tr').to_enum.with_index(1).each do |tr, index|
              tds = tr.css('td')
              case
              when tr.attr(:id).match?(/TXT_NAME/)   # airspace
                airspace = airspace_from tr
              when tds.count == 1   # big comment on separate row
                airspace.layers.first.remarks.
                  concat("\n", tds.text.cleanup).
                  remove!(/\((\d)\)\s*\(\1\)\W*/)
              else   # layer
                begin
                  tds = tr.css('td')
                  airspace.geometry = geometry_from tds[0].text
                  if airspace.geometry.point?   # convert point to circle
                    airspace.geometry = AIXM.geometry(
                      AIXM.circle(
                        center_xy: airspace.geometry.segments.first.xy,
                        radius: POINT_RADIUS
                      )
                    )
                  end
                  fail("geometry is not closed") unless airspace.geometry.closed?
                  airspace.add_layer layer_from(tds[1].text)
                  airspace.layers.first.timetable = timetable_from! tds[2].text
                  airspace.layers.first.remarks = remarks_from(tds[2], tds[3], tds[4])
                  if aixm.features.find_by(:airspace, type: airspace.type, id: airspace.id).none?
                    add airspace
                  end
                rescue => error
                  warn("error parsing airspace `#{airspace.name}' at ##{index}: #{error.message}", pry: error)
                end
              end
            end
          end
        end
      end

      private

      def airspace_from(tr)
        region, source_type, id = tr.css('td').first.text.cleanup.gsub(/\s/, ' ').split(nil, 3)
        id.remove!(/\W/)
        name = tr.css('td').last.text.cleanup.gsub(/\s/, ' ')
        fail "unknown type `#{source_type}'" unless SOURCE_TYPES.has_key? source_type
        AIXM.airspace(
          name: "#{region}-#{source_type}#{id} #{name}",
          type: SOURCE_TYPES.dig(source_type, :type),
          local_type: SOURCE_TYPES.dig(source_type, :local_type)
        ).tap do |airspace|
          airspace.source = source(position: tr.line)
        end
      end

      def remarks_from(*parts)
        part_titles = ['TIMETABLE', 'RESTRICTION', 'AUTHORITY/CONDITIONS']
        [].tap do |remarks|
          parts.each.with_index do |part, index|
            if part = part.text.gsub(/ +/, ' ').gsub(/(\n ?)+/, "\n").strip.blank_to_nil
              unless index.zero? && part == 'H24'
                remarks << "**#{part_titles[index]}**\n#{part}"
              end
            end
          end
        end.join("\n\n").blank_to_nil
      end
    end
  end
end
