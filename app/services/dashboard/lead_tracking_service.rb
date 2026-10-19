# frozen_string_literal: true

module Dashboard
  class LeadTrackingService
    def initialize(params:)
      @params = params
      @filters = Dashboard::FiltersBuilder.new(params: params)
    end

    def call
      time_range = @filters.time_range

      contacts = Contact.where(created_at: time_range)
      appointments = Appointment.where(start_time: time_range)

      if @params[:user_id].present? && @params[:user_id] != '__all__'
        appointments = appointments.where(user_id: @params[:user_id])
      end

      # Contact counts
      total_leads = contacts.count
      
      # Appointments breakdown
      total_scheduled = appointments.count
      total_attended = appointments.where(status: 'attended').count
      total_no_show = appointments.where(status: 'no_show').count
      total_confirmed = appointments.where(status: %w[confirmed scheduled]).count
      total_cancelled = appointments.where(status: 'cancelled').count

      # Contacts who scheduled
      scheduled_contact_ids = appointments.where.not(contact_id: nil).pluck(:contact_id).uniq
      attended_contact_ids = appointments.where(status: 'attended').where.not(contact_id: nil).pluck(:contact_id).uniq

      # Qualified leads (has appointment OR moved in pipeline)
      pipeline_contact_ids = PipelineItem.where(created_at: time_range).where.not(contact_id: nil).pluck(:contact_id).uniq
      qualified_contact_ids = (scheduled_contact_ids + pipeline_contact_ids).uniq
      total_qualified = qualified_contact_ids.count

      # Won leads
      won_pipeline_items = PipelineItem.joins(:pipeline_stage)
                                       .where(pipeline_stages: { stage_type: PipelineStage.stage_types[:completed] })
                                       .where(created_at: time_range)
      won_contact_ids = (attended_contact_ids + won_pipeline_items.pluck(:contact_id)).compact.uniq
      total_won = won_contact_ids.count

      # Financial calculations
      appointment_revenue = appointments.where(status: 'attended').sum(:price).to_f
      total_revenue = appointment_revenue
      avg_ticket = total_won.positive? ? (total_revenue / total_won).round(2) : 0.0

      # Conversion Rates
      qualification_rate = total_leads.positive? ? ((total_qualified.to_f / total_leads) * 100).round(1) : 0.0
      scheduling_rate = total_leads.positive? ? ((scheduled_contact_ids.count.to_f / total_leads) * 100).round(1) : 0.0
      total_shows_and_no_shows = total_attended + total_no_show
      show_rate = total_shows_and_no_shows.positive? ? ((total_attended.to_f / total_shows_and_no_shows) * 100).round(1) : (total_scheduled.positive? ? 100.0 : 0.0)
      conversion_rate = total_leads.positive? ? ((total_won.to_f / total_leads) * 100).round(1) : 0.0

      {
        period: {
          since: time_range.begin.to_i,
          until: time_range.end.to_i,
          days: ((time_range.end.to_date - time_range.begin.to_date).to_i + 1)
        },
        kpis: {
          total_leads: total_leads,
          total_qualified: total_qualified,
          total_scheduled: total_scheduled,
          total_attended: total_attended,
          total_no_show: total_no_show,
          total_confirmed: total_confirmed,
          total_cancelled: total_cancelled,
          total_won: total_won,
          qualification_rate: qualification_rate,
          scheduling_rate: scheduling_rate,
          show_rate: show_rate,
          conversion_rate: conversion_rate,
          total_revenue: total_revenue,
          average_ticket: avg_ticket
        },
        funnel: [
          { stage: 'Total de Leads', count: total_leads, percentage: 100.0, color: '#2A152F' },
          { stage: 'Qualificados', count: total_qualified, percentage: qualification_rate, color: '#5C2D63' },
          { stage: 'Agendados', count: scheduled_contact_ids.count, percentage: scheduling_rate, color: '#967AB4' },
          { stage: 'Compareceram', count: total_attended, percentage: total_leads.positive? ? ((total_attended.to_f / total_leads) * 100).round(1) : 0.0, color: '#3B82F6' },
          { stage: 'Convertidos / Venda', count: total_won, percentage: conversion_rate, color: '#10B981' }
        ],
        sources: build_sources(contacts, appointments),
        campaigns: build_campaigns(contacts, appointments),
        professionals: build_professionals(appointments),
        categories: build_categories(appointments),
        timeline: build_timeline(time_range, contacts, appointments)
      }
    end

    private

    def build_sources(contacts, appointments)
      sources_hash = Hash.new { |h, k| h[k] = { name: k, leads: 0, scheduled: 0, attended: 0, won: 0, revenue: 0.0 } }

      # Group contacts by utm_source or channel
      contacts.find_each do |contact|
        source = contact.custom_attributes&.dig('utm_source') || 
                 contact.additional_attributes&.dig('utm_source') || 
                 contact.custom_attributes&.dig('channel') || 
                 'Direto / Orgânico'
        sources_hash[source][:leads] += 1
      end

      # Connect appointments to sources via contacts
      contact_source_map = {}
      contacts.find_each do |c|
        src = c.custom_attributes&.dig('utm_source') || 
              c.additional_attributes&.dig('utm_source') || 
              c.custom_attributes&.dig('channel') || 
              'Direto / Orgânico'
        contact_source_map[c.id] = src
      end

      appointments.each do |apt|
        src = contact_source_map[apt.contact_id] || 'Direto / Orgânico'
        sources_hash[src][:scheduled] += 1
        if apt.status == 'attended'
          sources_hash[src][:attended] += 1
          sources_hash[src][:won] += 1
          sources_hash[src][:revenue] += apt.price.to_f
        end
      end

      # Provide default realistic channels if empty (new setup)
      if sources_hash.empty?
        return [
          { name: 'Instagram Ads', leads: 0, scheduled: 0, attended: 0, won: 0, revenue: 0.0, conversion_rate: 0.0 },
          { name: 'Google Ads', leads: 0, scheduled: 0, attended: 0, won: 0, revenue: 0.0, conversion_rate: 0.0 },
          { name: 'WhatsApp Direto', leads: 0, scheduled: 0, attended: 0, won: 0, revenue: 0.0, conversion_rate: 0.0 },
          { name: 'Indicação / Referral', leads: 0, scheduled: 0, attended: 0, won: 0, revenue: 0.0, conversion_rate: 0.0 }
        ]
      end

      sources_hash.values.map do |s|
        rate = s[:leads].positive? ? ((s[:won].to_f / s[:leads]) * 100).round(1) : 0.0
        s.merge(conversion_rate: rate)
      end.sort_by { |s| -s[:leads] }
    end

    def build_campaigns(contacts, appointments)
      campaigns_hash = Hash.new { |h, k| h[k] = { name: k, source: '', leads: 0, scheduled: 0, won: 0, revenue: 0.0 } }

      contact_campaign_map = {}
      contacts.find_each do |c|
        camp = c.custom_attributes&.dig('utm_campaign') || 'Padrão / Institucional'
        src = c.custom_attributes&.dig('utm_source') || 'Instagram'
        campaigns_hash[camp][:name] = camp
        campaigns_hash[camp][:source] = src
        campaigns_hash[camp][:leads] += 1
        contact_campaign_map[c.id] = camp
      end

      appointments.each do |apt|
        camp = contact_campaign_map[apt.contact_id] || 'Padrão / Institucional'
        campaigns_hash[camp][:scheduled] += 1
        if apt.status == 'attended'
          campaigns_hash[camp][:won] += 1
          campaigns_hash[camp][:revenue] += apt.price.to_f
        end
      end

      campaigns_hash.values.map do |c|
        rate = c[:leads].positive? ? ((c[:won].to_f / c[:leads]) * 100).round(1) : 0.0
        c.merge(conversion_rate: rate)
      end.sort_by { |c| -c[:revenue] }
    end

    def build_professionals(appointments)
      users = User.where(id: appointments.pluck(:user_id).uniq)
      user_map = users.index_by(&:id)

      prof_hash = Hash.new { |h, k| h[k] = { user_id: k, name: user_map[k]&.name || 'Profissional', total: 0, attended: 0, no_show: 0, revenue: 0.0 } }

      appointments.each do |apt|
        prof_hash[apt.user_id][:total] += 1
        case apt.status
        when 'attended'
          prof_hash[apt.user_id][:attended] += 1
          prof_hash[apt.user_id][:revenue] += apt.price.to_f
        when 'no_show'
          prof_hash[apt.user_id][:no_show] += 1
        end
      end

      prof_hash.values.map do |p|
        denom = p[:attended] + p[:no_show]
        rate = denom.positive? ? ((p[:attended].to_f / denom) * 100).round(1) : (p[:total].positive? ? 100.0 : 0.0)
        p.merge(show_rate: rate)
      end.sort_by { |p| -p[:revenue] }
    end

    def build_categories(appointments)
      cat_hash = Hash.new { |h, k| h[k] = { name: k, count: 0, revenue: 0.0, color: '#967AB4' } }

      # Preset colors from Appointment::CATEGORIES
      color_map = Appointment::CATEGORIES.each_with_object({}) { |c, acc| acc[c[:name]] = c[:color] }

      appointments.each do |apt|
        cat = apt.category || 'Geral'
        cat_hash[cat][:name] = cat
        cat_hash[cat][:count] += 1
        cat_hash[cat][:revenue] += apt.price.to_f if apt.status == 'attended'
        cat_hash[cat][:color] = color_map[cat] || '#967AB4'
      end

      total_count = appointments.count
      cat_hash.values.map do |c|
        share = total_count.positive? ? ((c[:count].to_f / total_count) * 100).round(1) : 0.0
        c.merge(share_percentage: share)
      end.sort_by { |c| -c[:count] }
    end

    def build_timeline(time_range, contacts, appointments)
      days = (time_range.begin.to_date..time_range.end.to_date).to_a
      
      # Limit to last 30 days if range is very long for chart readability
      days = days.last(30) if days.size > 30

      days.map do |d|
        start_d = d.beginning_of_day
        end_d = d.end_of_day

        day_leads = contacts.where('created_at >= ? AND created_at <= ?', start_d, end_d).count
        day_apts = appointments.where('start_time >= ? AND start_time <= ?', start_d, end_d)
        day_attended = day_apts.where(status: 'attended').count
        day_revenue = day_apts.where(status: 'attended').sum(:price).to_f

        {
          date: d.strftime('%Y-%m-%d'),
          label: d.strftime('%d/%m'),
          leads: day_leads,
          scheduled: day_apts.count,
          attended: day_attended,
          revenue: day_revenue
        }
      end
    end
  end
end
