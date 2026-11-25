# frozen_string_literal: true

module BusinessAssistant
  module_function

  # URL pública do backend que o n8n usa para chamar a API /assistant/v1.
  def base_url
    (ENV['BACKEND_URL'].presence || ENV.fetch('FRONTEND_URL', 'http://localhost:3000')).chomp('/')
  end

  def currency
    ENV.fetch('INSTALLATION_CURRENCY', 'BRL')
  end
end
