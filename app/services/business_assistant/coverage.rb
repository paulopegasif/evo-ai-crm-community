# frozen_string_literal: true

# Quanto dos dados tem origem identificada. Acompanha toda resposta de atribuição/tráfego para
# o agente avisar o dono quando a base é parcial (ex.: vendas fechadas fora do CRM).
module BusinessAssistant
  module Coverage
    module_function

    def for_period(period)
      sales = Sale.active.between(period.range)
      sales_total = sales.count
      sales_attributed = sales.joins(:contact).where(Sql.attributed_contact_condition).count
      leads = Queries::Leads.new_leads(period)
      leads_total = leads.count
      leads_attributed = leads.where(Sql.attributed_contact_condition).count

      {
        sales_with_source_pct: Sql.pct(sales_attributed, sales_total),
        sales_without_contact: sales.where(contact_id: nil).count,
        leads_with_source_pct: Sql.pct(leads_attributed, leads_total),
        ads_data_available: Sql.ads_data_available?
      }
    end
  end
end
