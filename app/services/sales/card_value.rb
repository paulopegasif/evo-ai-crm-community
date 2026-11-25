# frozen_string_literal: true

module Sales
  # Valor de um card: serviços (regra do Tracking) → produtos ligados → custom_fields['value'].
  module CardValue
    module_function

    def for(item)
      [item.services_total_value, item.total_value, item.custom_fields&.dig('value')]
        .map { |v| v.to_s.tr(',', '.').to_d }
        .find(&:positive?) || 0.to_d
    end
  end
end
