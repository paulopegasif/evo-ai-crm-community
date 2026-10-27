# frozen_string_literal: true

# Ensures a single Meta Ads sync runs at a time (manual and scheduled).
# The TTL frees the lock if a worker dies mid-sync.
module MetaAds::SyncLock
  module_function

  KEY = 'meta_ads:sync_lock'
  TTL = 30.minutes.to_i

  def acquire
    Redis::Alfred.set(KEY, Time.current.iso8601, nx: true, ex: TTL) ? true : false
  end

  def release
    Redis::Alfred.delete(KEY)
  end

  def locked?
    Redis::Alfred.exists?(KEY)
  rescue StandardError
    false
  end
end
