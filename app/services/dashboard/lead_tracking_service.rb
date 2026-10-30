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
  #
  # `source` and `campaign_key` narrow the lead cohort to one first-touch origin or
  # campaign and the paid media metrics to that Meta campaign; the period agenda is
  # never filtered by them.
  class LeadTrackingService
    DEFAULT_TIMEZONE = 'America/Sao_Paulo'
    PENDING_STATUSES = %w[scheduled confirmed rescheduled].freeze
    GRANULARITIES = %w[day week month].freeze
    # Longest period (in days) still charted per day / per week.
    DAILY_MAX_DAYS = 62
    WEEKLY_MAX_DAYS = 366
    MONTH_LABELS = %w[jan fev mar abr mai jun jul ago set out nov dez].freeze
    # Summed per campaign and period; reach is left out since daily reach does not add up.
    MEDIA_COLUMNS = %i[spend impressions link_clicks conversations meta_leads].freeze
    MEDIA_METRIC_KEYS = %i[impressions link_clicks ctr cpc cpm conversations cost_per_conversation meta_leads
                           cost_per_meta_lead].freeze

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
          timezone: @timezone,
          granularity: granularity,
          ads_history_from: ads_history_from
        },
        filter_options: filter_options,
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

    def source_filter
      @params[:source].presence
    end

    def campaign_filter
      @params[:campaign_key].presence
    end

    # --- Lead cohort --------------------------------------------------------------

    # Every lead of the period, before the source/campaign filters.
    def period_lead_ids
      @period_lead_ids ||= Contact.where(created_at: time_range).pluck(:id)
    end

    def cohort_ids
      @cohort_ids ||= period_lead_ids.select do |id|
        attribution = attribution_for(id)
        (source_filter.nil? || attribution[:source] == source_filter) &&
          (campaign_filter.nil? || attribution[:campaign_key] == campaign_filter)
      end
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
      @qualified_ids ||= begin
        advanced = PipelineItem.joins(:pipeline_stage)
                               .where(contact_id: cohort_ids)
                               .where('pipeline_stages.position > 1')
                               .where.not(pipeline_stages: { stage_type: PipelineStage.stage_types[:cancelled] })
                               .pluck(:contact_id)
        scheduled_ids | advanced.to_set
      end
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

    # --- Timeline -----------------------------------------------------------------

    def granularity
      @granularity ||= if GRANULARITIES.include?(@params[:granularity].to_s)
                         @params[:granularity].to_s
                       elsif period_days.size <= DAILY_MAX_DAYS
                         'day'
                       elsif period_days.size <= WEEKLY_MAX_DAYS
                         'week'
                       else
                         'month'
                       end
    end

    def bucket_start(day)
      case granularity
      when 'week' then day.beginning_of_week(:monday)
      when 'month' then day.beginning_of_month
      else day
      end
    end

    def bucket_label(start)
      case granularity
      when 'week' then "sem. #{start.strftime('%d/%m')}"
      when 'month' then "#{MONTH_LABELS[start.month - 1]}/#{start.strftime('%y')}"
      else start.strftime('%d/%m')
      end
    end

    def build_timeline
      leads = Contact.where(id: cohort_ids).pluck(:created_at).map { |at| bucket_start(at.to_date) }.tally
      agenda = agenda_rows.group_by { |row| bucket_start(row[4].to_date) }
      media = media_by_bucket

      period_days.group_by { |day| bucket_start(day) }.map do |start, days|
        rows = agenda.fetch(start, [])
        attended = rows.select { |row| row[1] == 'attended' }
        {
          date: days.first.iso8601,
          start_date: days.first.iso8601,
          end_date: days.last.iso8601,
          label: bucket_label(start),
          leads: leads.fetch(start, 0),
          scheduled: rows.count { |row| row[1] != 'cancelled' },
          attended: attended.size,
          revenue: attended.sum { |row| row[2].to_f }.round(2)
        }.merge(media.fetch(start, empty_media).except(:spend), spend: media.fetch(start, empty_media)[:spend].to_f.round(2))
      end
    end

    def media_by_bucket
      media_scope.group(:date).pluck(:date, *media_sums).each_with_object({}) do |(date, *values), acc|
        totals = acc[bucket_start(date)] ||= empty_media
        MEDIA_COLUMNS.zip(values).each { |column, value| totals[column] += value || 0 }
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

    # contact_id => { source:, campaign_key:, campaign_name:, meta_campaign_id:, from_ad: } for the period's leads.
    def attribution_map
      @attribution_map ||= Contact.where(id: period_lead_ids)
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
      campaign_media.each_key { |meta_id| row_for.call(meta_campaign_attribution(meta_id, meta_campaigns.dig(meta_id, :name))) }

      rows.values.map { |c| c.merge(campaign_metrics(c)) }
          .sort_by { |c| [-(c[:spend] || 0), -c[:revenue], -c[:leads]] }
    end

    # CRM outcome ratios plus the Meta delivery and results of one campaign row.
    # Media columns are nil for campaigns that are not Meta campaigns.
    def campaign_metrics(row)
      media = row[:meta_campaign_id] ? campaign_media.fetch(row[:meta_campaign_id], empty_media) : nil
      spend = media && media[:spend].to_f.round(2)
      conversations = media && media[:conversations].to_i
      {
        status: row[:meta_campaign_id] ? meta_campaigns.dig(row[:meta_campaign_id], :status) : nil,
        revenue: row[:revenue].round(2),
        conversion_rate: percent(row[:won], row[:leads]),
        spend: spend,
        cpl: ratio(spend, row[:leads]),
        cac: ratio(spend, row[:won]),
        roas: ratio(spend && row[:revenue], spend),
        lead_capture_rate: percent(row[:leads], conversations)
      }.merge(media_metrics(media))
    end

    def media_metrics(media)
      return MEDIA_METRIC_KEYS.index_with { nil } if media.nil?

      spend = media[:spend].to_f
      {
        impressions: media[:impressions].to_i,
        link_clicks: media[:link_clicks].to_i,
        ctr: percent(media[:link_clicks], media[:impressions], precision: 2),
        cpc: ratio(spend, media[:link_clicks]),
        cpm: ratio(spend * 1000, media[:impressions]),
        conversations: media[:conversations].to_i,
        cost_per_conversation: ratio(spend, media[:conversations]),
        meta_leads: media[:meta_leads].to_i,
        cost_per_meta_lead: ratio(spend, media[:meta_leads])
      }
    end

    # Spend KPIs are only meaningful when Meta Ads is (or was) connected, and never
    # for a source or campaign filter outside Meta.
    def ad_kpis
      totals = campaign_media.values.each_with_object(empty_media) do |media, acc|
        MEDIA_COLUMNS.each { |column| acc[column] += media[column] }
      end
      spend = totals[:spend].to_f
      ad_ids = cohort_ids.select { |id| attribution_for(id)[:from_ad] }
      ad_won = ad_ids.count { |id| won_ids.include?(id) }
      ad_revenue = ad_ids.sum { |id| cohort_revenue[id] }.round(2)
      conversations = totals[:conversations].to_i

      {
        ad_spend: spend.round(2),
        ad_leads: ad_ids.size,
        ad_won: ad_won,
        ad_revenue: ad_revenue,
        avg_cpl: ratio(spend, ad_ids.size),
        ad_cac: ratio(spend, ad_won),
        roas: ratio(ad_revenue, spend),
        lead_capture_rate: percent(ad_ids.size, conversations),
        has_ad_spend: !paid_media_excluded? && (MetaAds::Integration.current.present? || spend.positive?)
      }.merge(media_metrics(totals))
    end

    # --- Paid media (Meta insights) -----------------------------------------------

    def paid_media_excluded?
      (source_filter.present? && source_filter != SOURCE_LABELS['meta_ads']) ||
        (campaign_filter.present? && !campaign_filter.start_with?('meta:'))
    end

    def media_scope
      return MetaAds::InsightDaily.none if paid_media_excluded?

      scope = MetaAds::InsightDaily.where(date: period_days.first..period_days.last).where.not(meta_campaign_id: nil)
      campaign_filter ? scope.where(meta_campaign_id: campaign_filter.delete_prefix('meta:')) : scope
    end

    def media_sums
      MEDIA_COLUMNS.map { |column| Arel.sql("SUM(meta_ad_insights_daily.#{column})") }
    end

    def empty_media
      MEDIA_COLUMNS.index_with { 0 }
    end

    # meta_campaign_id => { spend:, impressions:, link_clicks:, conversations:, meta_leads: } in the period.
    def campaign_media
      @campaign_media ||= media_scope.group(:meta_campaign_id).pluck(:meta_campaign_id, *media_sums)
                                     .to_h { |meta_id, *values| [meta_id, MEDIA_COLUMNS.zip(values.map { |v| v || 0 }).to_h] }
    end

    # meta_id => { name:, status: } for campaigns with delivery in the period.
    def meta_campaigns
      @meta_campaigns ||= MetaAds::Campaign.where(meta_id: campaign_media.keys)
                                           .pluck(:meta_id, :name, :effective_status)
                                           .to_h { |meta_id, name, status| [meta_id, { name: name, status: status }] }
    end

    def ads_history_from
      MetaAds::Integration.current&.history_synced_from
    end

    # --- Filter options -------------------------------------------------------------

    # Sources and campaigns of the period, regardless of the source/campaign filters,
    # so the user can always switch to another option.
    def filter_options
      attributions = period_lead_ids.map { |id| attribution_for(id) }
      campaigns = attributions.to_h { |a| [a[:campaign_key], { key: a[:campaign_key], name: a[:campaign_name], source: a[:source] }] }
      meta_options = delivered_campaign_options
      sources = attributions.pluck(:source).uniq
      sources |= [SOURCE_LABELS['meta_ads']] if meta_options.any?

      { sources: sources.sort, campaigns: meta_options.merge(campaigns).values.sort_by { |c| c[:name].downcase } }
    end

    # Meta campaigns with delivery in the period (any filter), as campaign options.
    def delivered_campaign_options
      ids = MetaAds::InsightDaily.where(date: period_days.first..period_days.last).where.not(meta_campaign_id: nil)
                                 .distinct.pluck(:meta_campaign_id)
      names = MetaAds::Campaign.where(meta_id: ids).pluck(:meta_id, :name).to_h
      ids.to_h do |id|
        ["meta:#{id}", { key: "meta:#{id}", name: names[id].presence || "Campanha #{id}", source: SOURCE_LABELS['meta_ads'] }]
      end
    end

    def percent(part, whole, precision: 1)
      return nil if whole.to_f.zero?

      ((part.to_f / whole) * 100).round(precision)
    end

    def ratio(numerator, denominator, precision: 2)
      return nil if numerator.nil? || denominator.nil? || denominator.to_f.zero?

      (numerator.to_f / denominator.to_f).round(precision)
    end
  end
end
