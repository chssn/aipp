module AIPP
  module LF
    module Helpers
      module ADRadio

        # Service types to be ignored
        IGNORED_TYPES = %w(D-ATIS).freeze

        # Service types to be encoded as addresses
        ADDRESS_TYPES = %w(A/A A/G).freeze

        # Unknown service types to be encoded as units
        SERVICE_TYPES = {
          'CEV' => { type: :other, remarks: "CEV (centre d'essais en vol / flight test center)" },
          'SRE' => { type: :other, remarks: "SRE (elément radar de surveillance du PAR / surveillance radar element of PAR)" }
        }.freeze

        def parts_from(tds)
          {
            f: AIXM.f(tds[2].css('span').first.text.to_f, tds[2].css('span').last.text),
            callsign: tds[1].text.strip,
            timetable: tds[3].text.strip,
            remarks: tds[4].text.strip.sub(/Canal (8.33|25)/i, '')   # TEMP: ignore canal spacing warnings
          }
        end

        def addresses_from(trs)
          trs.map do |tr|
            tds = tr.css('td')
            type = tds[0].text.strip
            next if IGNORED_TYPES.include? type
            f, callsign, _, remarks = parts_from(tds).values
            if ADDRESS_TYPES.include?(type)
              AIXM.address(
                source: source(position: tr.line),
                type: :radio_frequency,
                address: f.to_s
              ).tap do |address|
                address.remarks = ["#{type} - indicatif/callsign #{callsign}", remarks.blank_to_nil].compact.join("\n")
              end
            end
          end.compact
        end

        def units_from(trs)
          trs.each_with_object({}) do |tr, services|
            tds = tr.css('td')
            type = tds[0].text.strip
            next if IGNORED_TYPES.include?(type) || ADDRESS_TYPES.include?(type)
            f, callsign, timetable, remarks = parts_from(tds).values
            if SERVICE_TYPES.include? type
              type = SERVICE_TYPES.dig(type, :type)
              remarks = [SERVICE_TYPES.dig(type, :remarks), remarks.blank_to_nil].compact.join("\n")
            end
            unless services.include? type
              services[type] = AIXM.service(
                source: source(position: tr.line),
                type: type
              )
            end
            code = $1 if timetable.sub!(/(#{AIXM::H_RE})\b/, '')
            services[type].add_frequency(
              AIXM.frequency(
                transmission_f: f,
                callsigns: { fr: callsign }
              ).tap do |frequency|
                frequency.type = :standard
                frequency.type = :alternative if remarks.sub!(%r{fréquence supplétive/auxiliary frequency\S*}i, '')
                frequency.timetable = AIXM.timetable(code: code) if code
                frequency.remarks = [remarks, timetable.blank_to_nil].compact.join("\n").cleanup.blank_to_nil
              end
            )
          end.values.map do |service|
            AIXM.unit(
              source: service.source,
              organisation: organisation_lf,   # TODO: not yet implemented
              type: (type = service.guessed_unit_type),
              name: "#{@id} #{AIXM::Feature::Unit::TYPES.key(type)}",
              class: :icao   # TODO: verify whether all units are ICAO
            ).tap do |unit|
              unit.airport = @airport
              unit.add_service(service)
            end
          end
        end

      end
    end
  end
end