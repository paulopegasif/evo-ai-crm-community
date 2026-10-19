# frozen_string_literal: true

user = User.first
raise "Nenhum usuário encontrado no sistema!" unless user

puts "==> Populando dados reais para Lumom Beauty com profissional: #{user.name} (#{user.email})"

leads_data = [
  {
    name: 'Juliana Mendes',
    email: 'juliana.mendes@gmail.com',
    phone_number: '+5511987654321',
    custom_attributes: {
      'utm_source' => 'instagram',
      'utm_medium' => 'stories',
      'utm_campaign' => 'harmonizacao-abril',
      'utm_content' => 'video_antes_depois',
      'channel' => 'Instagram'
    }
  },
  {
    name: 'Mariana Costa',
    email: 'mariana.costa@hotmail.com',
    phone_number: '+5511976543210',
    custom_attributes: {
      'utm_source' => 'google_ads',
      'utm_medium' => 'cpc',
      'utm_campaign' => 'botox-preventivo',
      'utm_term' => 'clinica botox sp',
      'channel' => 'WhatsApp'
    }
  },
  {
    name: 'Carolina Ferreira',
    email: 'carol.ferreira@outlook.com',
    phone_number: '+5511965432109',
    custom_attributes: {
      'utm_source' => 'instagram',
      'utm_medium' => 'reels',
      'utm_campaign' => 'harmonizacao-abril',
      'channel' => 'Instagram'
    }
  },
  {
    name: 'Beatriz Santos',
    email: 'beatriz.santos@gmail.com',
    phone_number: '+5511954321098',
    custom_attributes: {
      'utm_source' => 'indicacao',
      'utm_medium' => 'amiga',
      'utm_campaign' => 'boca-a-boca',
      'channel' => 'WhatsApp'
    }
  },
  {
    name: 'Fernanda Lima',
    email: 'fernanda.lima@uol.com.br',
    phone_number: '+5511943210987',
    custom_attributes: {
      'utm_source' => 'tiktok',
      'utm_medium' => 'video_viral',
      'utm_campaign' => 'limpeza-pele-glow',
      'channel' => 'Webchat'
    }
  },
  {
    name: 'Renata Oliveira',
    email: 'renata.oliveira@gmail.com',
    phone_number: '+5511932109876',
    custom_attributes: {
      'utm_source' => 'facebook_ads',
      'utm_medium' => 'feed',
      'utm_campaign' => 'bioestimulador-firmeza',
      'channel' => 'Facebook'
    }
  },
  {
    name: 'Amanda Rocha',
    email: 'amanda.rocha@gmail.com',
    phone_number: '+5511921098765',
    custom_attributes: {
      'utm_source' => 'google_ads',
      'utm_medium' => 'cpc',
      'utm_campaign' => 'laser-manchas',
      'channel' => 'WhatsApp'
    }
  },
  {
    name: 'Larissa Guimarães',
    email: 'larissa.guimaraes@yahoo.com',
    phone_number: '+5511910987654',
    custom_attributes: {
      'utm_source' => 'instagram',
      'utm_medium' => 'bio',
      'utm_campaign' => 'avaliacao-gratuita',
      'channel' => 'Instagram'
    }
  }
]

created_contacts = {}
leads_data.each do |ld|
  contact = Contact.find_or_initialize_by(email: ld[:email])
  contact.name = ld[:name]
  contact.phone_number = ld[:phone_number]
  contact.custom_attributes = ld[:custom_attributes]
  contact.created_at = (rand(1..15)).days.ago
  contact.save(validate: false)
  created_contacts[ld[:name]] = contact
  puts "Contato criado/atualizado: #{contact.name} (#{contact.id})"
end

# Criar agendamentos realistas para Lumom Beauty
now = Time.current

appointments_seed = [
  {
    title: 'Harmonização Facial - Juliana Mendes',
    category: 'Harmonização Facial',
    contact: created_contacts['Juliana Mendes'],
    start_time: now.beginning_of_day + 10.hours,
    duration_minutes: 90,
    status: 'confirmed',
    price: 1800.0,
    location: 'Consultório 1 - Lumom Beauty',
    description: 'Preenchimento malar e mandíbula. Paciente confirmou por WhatsApp.'
  },
  {
    title: 'Limpeza de Pele Profunda - Mariana Costa',
    category: 'Limpeza de Pele Profunda',
    contact: created_contacts['Mariana Costa'],
    start_time: now.beginning_of_day + 14.hours,
    duration_minutes: 60,
    status: 'scheduled',
    price: 220.0,
    location: 'Sala Estética 2',
    description: 'Protocolo Glow com extração por sucção e máscara calmante.'
  },
  {
    title: 'Toxina Botulínica (Botox) - Carolina Ferreira',
    category: 'Toxina Botulínica (Botox)',
    contact: created_contacts['Carolina Ferreira'],
    start_time: now.beginning_of_day + 16.hours,
    duration_minutes: 45,
    status: 'scheduled',
    price: 1200.0,
    location: 'Consultório 1 - Lumom Beauty',
    description: 'Aplicação terço superior (glabela, frontal e peri-orbicular).'
  },
  {
    title: 'Bioestimulador de Colágeno - Beatriz Santos',
    category: 'Bioestimulador de Colágeno',
    contact: created_contacts['Beatriz Santos'],
    start_time: 1.day.ago.beginning_of_day + 11.hours,
    duration_minutes: 60,
    status: 'attended',
    price: 1500.0,
    location: 'Consultório 1 - Lumom Beauty',
    description: 'Aplicação de Radiesse em terço médio e inferior. Sessão concluída com sucesso.'
  },
  {
    title: 'Avaliação Facial - Fernanda Lima',
    category: 'Avaliação Facial',
    contact: created_contacts['Fernanda Lima'],
    start_time: 1.day.ago.beginning_of_day + 15.hours,
    duration_minutes: 45,
    status: 'attended',
    price: 100.0,
    location: 'Consultório 1 - Lumom Beauty',
    description: 'Avaliação dermatológica e plano de tratamento facial montado.'
  },
  {
    title: 'Laser & Luz Pulsada - Renata Oliveira',
    category: 'Laser & Luz Pulsada',
    contact: created_contacts['Renata Oliveira'],
    start_time: 2.days.ago.beginning_of_day + 10.hours,
    duration_minutes: 45,
    status: 'attended',
    price: 350.0,
    location: 'Sala Laser',
    description: 'Sessão 2/4 para tratamento de melasma e poros dilatados.'
  },
  {
    title: 'Avaliação Facial - Amanda Rocha',
    category: 'Avaliação Facial',
    contact: created_contacts['Amanda Rocha'],
    start_time: 3.days.ago.beginning_of_day + 14.hours,
    duration_minutes: 45,
    status: 'no_show',
    price: 100.0,
    location: 'Consultório 1 - Lumom Beauty',
    description: 'Paciente não compareceu e não avisou. Equipe tentando reagendamento.'
  },
  {
    title: 'Avaliação Facial - Larissa Guimarães',
    category: 'Avaliação Facial',
    contact: created_contacts['Larissa Guimarães'],
    start_time: 1.day.from_now.beginning_of_day + 9.hours + 30.minutes,
    duration_minutes: 45,
    status: 'scheduled',
    price: 100.0,
    location: 'Consultório 1 - Lumom Beauty',
    description: 'Interesse em rejuvenescimento facial e botox.'
  },
  {
    title: 'Retorno / Revisão - Juliana Mendes',
    category: 'Retorno / Acompanhamento',
    contact: created_contacts['Juliana Mendes'],
    start_time: 3.days.from_now.beginning_of_day + 11.hours,
    duration_minutes: 30,
    status: 'scheduled',
    price: 0.0,
    location: 'Consultório 1 - Lumom Beauty',
    description: 'Revisão de 15 dias da harmonização facial.'
  }
]

Appointment.destroy_all

appointments_seed.each do |apt_data|
  start_t = apt_data[:start_time]
  dur = apt_data[:duration_minutes]
  end_t = start_t + dur.minutes

  apt = Appointment.create!(
    title: apt_data[:title],
    category: apt_data[:category],
    contact: apt_data[:contact],
    user: user,
    start_time: start_t,
    end_time: end_t,
    duration_minutes: dur,
    status: apt_data[:status],
    price: apt_data[:price],
    location: apt_data[:location],
    description: apt_data[:description],
    google_calendar_sync_status: apt_data[:status] == 'attended' ? 'synced' : 'pending'
  )
  puts "Agendamento criado: #{apt.title} (#{apt.status}) - #{apt.start_time.strftime('%d/%m %H:%M')}"
end

puts "==> Sucesso! #{Appointment.count} agendamentos e #{Contact.count} contatos criados para Lumom Beauty."
