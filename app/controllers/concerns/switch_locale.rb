module SwitchLocale
  extend ActiveSupport::Concern

  private

  def switch_locale(&)
    # priority is for locale set in query string (mostly for widget/from js sdk)
    locale ||= params[:locale]

    # if locale is not set, use DEFAULT_LOCALE env variable or Rails default
    locale ||= ENV.fetch('DEFAULT_LOCALE', nil)
    set_locale(locale, &)
  end

  def switch_locale_using_default(&)
    locale = ENV.fetch('DEFAULT_LOCALE', I18n.default_locale.to_s)
    set_locale(locale, &)
  end

  def set_locale(locale, &)
    safe_locale = validate_and_get_locale(locale)
    # Ensure locale won't bleed into other requests
    # https://guides.rubyonrails.org/i18n.html#managing-the-locale-across-requests
    I18n.with_locale(safe_locale, &)
  end

  def validate_and_get_locale(locale)
    return I18n.default_locale.to_s if locale.blank?

    available_locales = I18n.available_locales.map(&:to_s)
    # Accept BCP-47 style codes ("pt-BR") for our underscore locales ("pt_BR").
    # DEFAULT_LOCALE=pt-BR silently fell back to English before.
    locale = locale.to_s.tr('-', '_')
    locale_without_variant = locale.split('_')[0]

    if available_locales.include?(locale)
      locale
    elsif available_locales.include?(locale_without_variant)
      locale_without_variant
    else
      I18n.default_locale.to_s
    end
  end
end
