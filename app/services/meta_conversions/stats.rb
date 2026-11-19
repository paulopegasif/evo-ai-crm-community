# frozen_string_literal: true

# Delivery summary for the integrations page, read from the per-contact log the
# SendService keeps in contacts.additional_attributes.meta_capi.
module MetaConversions::Stats
  module_function

  WINDOW = 30.days

  ENTRIES_SQL = <<~SQL.squish
    SELECT e.value->>'event' AS event,
           e.value->>'sent_at' AS sent_at,
           e.value->>'failed_at' AS failed_at,
           e.value->>'error' AS error
    FROM contacts
    CROSS JOIN LATERAL jsonb_each(contacts.additional_attributes->'meta_capi') AS e
    WHERE jsonb_typeof(contacts.additional_attributes->'meta_capi') = 'object'
      AND jsonb_typeof(e.value) = 'object'
      AND COALESCE(e.value->>'sent_at', e.value->>'failed_at') >= :since
  SQL

  def call(since: WINDOW.ago)
    rows = entries(since)
    sent, failed = rows.partition { |r| r['sent_at'].present? }

    {
      window_days: (WINDOW / 1.day).to_i,
      sent: sent.size,
      failed: failed.size,
      by_event: by_event(rows),
      last_sent_at: sent.pluck('sent_at').max,
      last_failure: last_failure(failed)
    }
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.error("MetaConversions::Stats: #{e.message}")
    nil
  end

  def entries(since)
    Contact.connection.select_all(Contact.sanitize_sql([ENTRIES_SQL, { since: since.iso8601 }])).to_a
  end

  def by_event(rows)
    rows.group_by { |r| r['event'] }.transform_values do |list|
      sent = list.count { |r| r['sent_at'].present? }
      { sent: sent, failed: list.size - sent }
    end
  end

  def last_failure(failed)
    row = failed.max_by { |r| r['failed_at'].to_s }
    row && { event: row['event'], error: row['error'], at: row['failed_at'] }
  end
end
