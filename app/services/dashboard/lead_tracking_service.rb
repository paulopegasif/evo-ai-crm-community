# frozen_string_literal: true

module Dashboard
  # Lead tracking dashboard. Two populations that are never mixed:
  #
  # - Lead cohort: contacts created in the period, followed through all of their
  #   appointments (any date). Feeds the funnel, sources, campaigns and ad ROI,
  #   so every stage is a subset of the previous one.
  # - Period agenda: appointments whose start_time falls in the period. Feeds the
  #   show rate, revenue, procedures and professionals.
  #
  # Day boundaries follow the viewer's `timezone` param. Ratios are nil (rendered
  # as "—") when their denominator is zero.
  class LeadTrackingService
    DEFAULT_TIMEZONE = 'America/Sao_Paulo'
    PENDING_STATUSES = %w[scheduled confirmed rescheduled].freeze

    def initialize(params:)
      @params = params
      zone = params[:timezone].to_s
      @timezone = ActiveSupport::TimeZone[zone] ? zone : DEFAULT_TIMEZONE
    end

    def call
      Time.use_zone(@timezone) { build }
    end

    private

    def build
      @filters = Dashboard::FiltersBuilder.new(params: @params)

      {
        period: {
          since: time_range.begin.to_i,
          until: time_range.end.to_i,
          days: period_days.size,
          timezone: @timezone
        },
        kpis: cohort_kpis.merge(agenda_kpis).merge(ad_kpis),
        funnel: build_funnel,
        sources: build_sources,
        campaigns: build_campaigns,
        professionals: build_professionals,
        categories: build_categories,
        timeline: build_timeline
      }
    end

    def time_range
      @filters.time_range
    end

    def period_days
      @period_days ||= (time_range.begin.to_date..time_range.end.to_date).to_a
    end

    def professional_id
      id = @params[:user_id]
      id if id.present? && id != '__all__'
    end

    def for_professional(scope)
      professional_id ? scope.where(user_id: professional_id) : scope
    end

    # --- Lead cohort --------------------------------------------------------------

    def cohort_ids
      @cohort_ids ||= Contact.where(created_at: time_range).pluck(:id)
    end

    # [contact_id, status, price] of the cohort's non-cancelled appointments.
    def cohort_appointment_rows
      @cohort_appointment_rows ||= for_professional(Appointment.where(contact_id: cohort_ids))
                                   .where.not(status: 'cancelled')
                                   .pluck(:contact_id, :status, :price)
    end

    def scheduled_ids
      @scheduled_ids ||= cohort_appointment_rows.to_set(&:first)
    end

    def attended_ids
      @attended_ids ||= cohort_appointment_rows.filter_map { |id, status, _| id if status == 'attended' }.to_set
    end

    def qualified_ids
      @qualified_ids ||= scheduled_ids | PipelineItem.where(contact_id: cohort_ids).pluck(:contact_id).to_set
    end

    # Attended and either paid for the procedure or closed in a completed pipeline stage.
    def won_ids
      @won_ids ||= begin
        paid = cohort_appointment_rows.filter_map { |id, status, price| id if status == 'attended' && price.to_f.positive? }
        closed = PipelineItem.joins(:pipeline_stage)
                             .where(contact_id: cohort_ids, pipeline_stages: { stage_type: PipelineStage.stage_types[:completed] })
                             .pluck(:contact_id)
        attended_ids & (paid.to_set | closed.to_set)
      end
    end

    # contact_id => revenue of the attended appointments of that lead.
    def cohort_revenue
      @cohort_revenue ||= cohort_appointment_rows.each_with_object(Hash.new(0.0)) do |(id, status, price), acc|
        acc[id] += price.to_f if status == 'attended'
      end
    end

    def cohort_kpis
      total = cohort_ids.size
      {
        total_leads: total,
        total_qualified: qualified_ids.size,
        total_scheduled: scheduled_ids.size,
        total_attended: attended_ids.size,
        total_won: won_ids.size,
        qualification_rate: percent(qualified_ids.size, total),
        scheduling_rate: percent(scheduled_ids.size, total),
        conversion_rate: percent(won_ids.size, total),
        cohort_revenue: cohort_revenue.values.sum.round(2)
      }
    end

    def build_funnel
      stages = [
        ['leads', 'Leads', cohort_ids.size],
        ['qualified', 'Qualificados', qualified_ids.size],
        ['scheduled', 'Agendaram', scheduled_ids.size],
        ['attended', 'Compareceram', attended_ids.size],
        ['won', 'Converteram', won_ids.size]
      ]

      stages.each_with_index.map do |(key, label, count), index|
        {
          key: key,
          stage: label,
          count: count,
          percentage: percent(count, cohort_ids.size),
          step_rate: index.zero? ? nil : percent(count, stages[index - 1][2])
        }
      end
    end

    # --- Period agenda ------------------------------------------------------------

    # [user_id, status, price, category, start_time] of appointments in the period.
    def agenda_rows
      @agenda_rows ||= for_professional(Appointment.where(start_time: time_range))
                       .pluck(:user_id, :status, :price, :category, :start_time)
    end

    def agenda_kpis
      counts = agenda_rows.map(&:second).tally
      attended = counts.fetch('attended', 0)
      no_show = counts.fetch('no_show', 0)
      paid = agenda_rows.count { |_, status, price| status == 'attended' && price.to_f.positive? }
      revenue = agenda_revenue

      {
        total_appointments: agenda_rows.size,
        total_confirmed: counts.fetch('confirmed', 0),
        total_pending: PENDING_STATUSES.sum { |status| counts.fetch(status, 0) },
        appointments_attended: attended,
        total_no_show: no_show,
        total_cancelled: counts.fetch('cancelled', 0),
        show_rate: percent(attended, attended + no_show),
        total_revenue: revenue,
        paid_appointments: paid,
        average_ticket: ratio(revenue, paid)
      }
    end

    def agenda_revenue
      agenda_rows.sum { |_, status, price, _, _| status == 'attended' ? price.to_f : 0.0 }.round(2)
    end

    def build_professionals
      names = User.where(id: agenda_rows.map(&:first).uniq).pluck(:id, :name).to_h

      agenda_rows.group_by(&:first).map do |user_id, rows|
        counts = rows.map(&:second).tally
        attended = counts.fetch('attended', 0)
        no_show = counts.fetch('no_show', 0)
        {
          user_id: user_id,
          name: names[user_id] || 'Profissional',
          total: rows.size,
          attended: attended,
          no_show: no_show,
          cancelled: counts.fetch('cancelled', 0),
          pending: PENDING_STATUSES.sum { |status| counts.fetch(status, 0) },
          show_rate: percent(attended, attended + no_show),
          revenue: rows.sum { |_, status, price, _, _| status == 'attended' ? price.to_f : 0.0 }.round(2)
        }
      end.sort_by { |p| [-p[:revenue], -p[:total]] }
    end

    def build_categories
      colors = Appointment::CATEGORIES.to_h { |c| [c[:name], c[:color]] }
      rows = agenda_rows.reject { |_, status, _, _, _| status == 'cancelled' }
      total_revenue = agenda_revenue

      rows.group_by { |row| row[3].presence || 'Geral' }.map do |name, group|
        attended = group.select { |row| row[1] == 'attended' }
        revenue = attended.sum { |row| row[2].to_f }.round(2)
        {
          name: name,
          color: colors[name] || '#967AB4',
          count: group.size,
          attended: attended.size,
          revenue: revenue,
          share_percentage: percent(group.size, rows.size),
          revenue_share: percent(revenue, total_revenue)
        }
      end.sort_by { |c| [-c[:revenue], -c[:count]] }
    end

    def build_timeline
      leads = Contact.where(id: cohort_ids).pluck(:created_at).map(&:to_date).tally
      agenda = agenda_rows.group_by { |row| row[4].to_date }
      spend = MetaAds::InsightDaily.where(date: period_days).group(:date).sum(:spend)

      period_days.map do |day|
        rows = agenda.fetch(day, [])
        attended = rows.select { |row| row[1] == 'attended' }
        {
          date: day.iso8601,
          label: day.strftime('%d/%m'),
          leads: leads.fetch(day, 0),
          scheduled: rows.count { |row| row[1] != 'cancelled' },
          attended: attended.size,
          revenue: attended.sum { |row| row[2].to_f }.round(2),
          spend: spend.fetch(day, 0).to_f
        }
      end
    end

    # --- Attribution (first touch; see Attribution::RecordService) ----------------

    SOURCE_SQL = "COALESCE(NULLIF(contacts.additional_attributes->>'utm_source', ''), " \
                 "NULLIF(contacts.custom_attributes->>'utm_source', ''), " \
                 "NULLIF(contacts.custom_attributes->>'channel', ''))"
    UTM_CAMPAIGN_SQL = "COALESCE(NULLIF(contacts.additional_attributes->>'utm_campaign', ''), " \
                       "NULLIF(contacts.custom_attributes->>'utm_campaign', ''))"
    AD_ID_SQL = "NULLIF(contacts.additional_attributes->>'ad_id', '')"
    SOURCE_LABELS = { 'meta_ads' => 'Meta Ads' }.freeze
    UNKNOWN_SOURCE = 'Não informada'
    NO_CAMPAIGN = 'Sem campanha'

    def attribution_for(contact_id)
      attribution_map[contact_id] || no_attribution
    end

    # contact_id => { source:, campaign_key:, campaign_name:, meta_campaign_id:, from_ad: } for the cohort.
    def attribution_map
      @attribution_map ||= Contact.where(id: cohort_ids)
                                  .joins('LEFT JOIN meta_ads ON meta_ads.meta_id = contacts.additional_attributes->>\'ad_id\'')
                                  .joins('LEFT JOIN meta_campaigns ON meta_campaigns.meta_id = meta_ads.meta_campaign_id')
                                  .pluck(Arel.sql('contacts.id'), Arel.sql(SOURCE_SQL), Arel.sql(AD_ID_SQL),
                                         Arel.sql(UTM_CAMPAIGN_SQL), Arel.sql('meta_campaigns.meta_id'),
                                         Arel.sql('meta_campaigns.name'))
                                  .to_h { |id, *attrs| [id, build_attribution(*attrs)] }
    end

    def build_attribution(source, ad_id, utm_campaign, meta_campaign_id, meta_campaign_name)
      return meta_campaign_attribution(meta_campaign_id, meta_campaign_name) if meta_campaign_id.present?

      source_label = SOURCE_LABELS.fetch(source, source.presence || UNKNOWN_SOURCE)
      key, name = if ad_id.present?
                    ["ad:#{ad_id}", "Anúncio #{ad_id}"]
                  elsif utm_campaign.present?
                    ["utm:#{utm_campaign}", utm_campaign]
                  else
                    ['none', NO_CAMPAIGN]
                  end
      { source: source_label, campaign_key: key, campaign_name: name, meta_campaign_id: nil,
        from_ad: ad_id.present? || source == 'meta_ads' }
    end

    def meta_campaign_attribution(meta_id, name)
      { source: SOURCE_LABELS['meta_ads'], campaign_key: "meta:#{meta_id}", campaign_name: name.presence || "Campanha #{meta_id}",
        meta_campaign_id: meta_id, from_ad: true }
    end

    def no_attribution
      { source: UNKNOWN_SOURCE, campaign_key: 'none', campaign_name: NO_CAMPAIGN, meta_campaign_id: nil, from_ad: false }
    end

    # Cohort outcome counters for one group of leads.
    def empty_outcome
      { leads: 0, scheduled: 0, attended: 0, won: 0, revenue: 0.0 }
    end

    def add_lead(row, contact_id)
      row[:leads] += 1
      row[:scheduled] += 1 if scheduled_ids.include?(contact_id)
      row[:attended] += 1 if attended_ids.include?(contact_id)
      row[:won] += 1 if won_ids.include?(contact_id)
      row[:revenue] += cohort_revenue[contact_id]
    end

    def build_sources
      rows = Hash.new { |h, name| h[name] = { name: name }.merge(empty_outcome) }
      cohort_ids.each { |id| add_lead(rows[attribution_for(id)[:source]], id) }

      rows.values.map do |s|
        s.merge(revenue: s[:revenue].round(2), conversion_rate: percent(s[:won], s[:leads]),
                share_percentage: percent(s[:leads], cohort_ids.size))
      end.sort_by { |s| -s[:leads] }
    end

    def build_campaigns
      rows = {}
      row_for = lambda do |attribution|
        rows[attribution[:campaign_key]] ||= {
          campaign_key: attribution[:campaign_key],
          meta_campaign_id: attribution[:meta_campaign_id],
          name: attribution[:campaign_name],
          source: attribution[:source]
        }.merge(empty_outcome)
      end

      cohort_ids.each { |id| add_lead(row_for.call(attribution_for(id)), id) }
      # Campaigns that spent in the period without any attributed lead still show up.
      campaign_spend.each_key { |meta_id| row_for.call(meta_campaign_attribution(meta_id, meta_campaign_names[meta_id])) }

      rows.values.map do |c|
        spend = c[:meta_campaign_id] ? campaign_spend[c[:meta_campaign_id]]&.to_f : nil
        c.merge(
          revenue: c[:revenue].round(2),
          conversion_rate: percent(c[:won], c[:leads]),
          spend: spend,
          cpl: ratio(spend, c[:leads]),
          cac: ratio(spend, c[:won]),
          roas: ratio(spend && c[:revenue], spend)
        )
      end.sort_by { |c| [-(c[:spend] || 0), -c[:revenue], -c[:leads]] }
    end

    # Spend KPIs are only meaningful when Meta Ads is (or was) connected.
    def ad_kpis
      spend = campaign_spend.values.sum.to_f
      ad_ids = cohort_ids.select { |id| attribution_for(id)[:from_ad] }
      ad_won = ad_ids.count { |id| won_ids.include?(id) }
      ad_revenue = ad_ids.sum { |id| cohort_revenue[id] }.round(2)

      {
        ad_spend: spend.round(2),
        ad_leads: ad_ids.size,
        ad_won: ad_won,
        ad_revenue: ad_revenue,
        avg_cpl: ratio(spend, ad_ids.size),
        ad_cac: ratio(spend, ad_won),
        roas: ratio(ad_revenue, spend),
        has_ad_spend: MetaAds::Integration.current.present? || spend.positive?
      }
    end

    # meta_campaign_id => spend (BigDecimal) within the period's calendar days.
    def campaign_spend
      @campaign_spend ||= MetaAds::InsightDaily
                          .where(date: period_days.first..period_days.last)
                          .where.not(meta_campaign_id: nil)
                          .group(:meta_campaign_id)
                          .sum(:spend)
    end

    def meta_campaign_names
      @meta_campaign_names ||= MetaAds::Campaign.where(meta_id: campaign_spend.keys).pluck(:meta_id, :name).to_h
    end

    def percent(part, whole)
      return nil if whole.to_f.zero?

      ((part.to_f / whole) * 100).round(1)
    end

    def ratio(numerator, denominator, precision: 2)
      return nil if numerator.nil? || denominator.nil? || denominator.to_f.zero?

      (numerator.to_f / denominator.to_f).round(precision)
    end
  end
end
