require 'rails_helper'

RSpec.describe SwitchLocale do
  subject(:host) { Class.new { include SwitchLocale }.new }

  def resolve(locale) = host.send(:validate_and_get_locale, locale)

  it 'accepts the underscore code' do
    expect(resolve('pt_BR')).to eq('pt_BR')
  end

  it 'accepts the BCP-47 hyphen code used in DEFAULT_LOCALE' do
    expect(resolve('pt-BR')).to eq('pt_BR')
  end

  it 'falls back to the language without variant' do
    expect(resolve('es-MX')).to eq('es')
  end

  it 'falls back to the default locale for unknown or blank codes' do
    expect(resolve('xx')).to eq(I18n.default_locale.to_s)
    expect(resolve(nil)).to eq(I18n.default_locale.to_s)
  end
end
