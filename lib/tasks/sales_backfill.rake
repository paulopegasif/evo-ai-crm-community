# frozen_string_literal: true

# Painel do Dia: cria vendas para cards já ganhos antes do recurso existir.
#   bundle exec rake sales:backfill_from_pipeline            # simulação (não grava)
#   CONFIRM=1 bundle exec rake sales:backfill_from_pipeline  # grava
namespace :sales do
  desc 'Cria vendas automáticas para cards já em estágio ganho (dry-run sem CONFIRM=1)'
  task backfill_from_pipeline: :environment do
    dry_run = ENV['CONFIRM'] != '1'
    result = Sales::BackfillService.new(dry_run: dry_run).call
    prefix = dry_run ? '[simulação] ' : ''
    puts "#{prefix}Vendas a criar: #{result.created} (R$ #{format('%.2f', result.total_amount)}); " \
         "cards já com venda: #{result.skipped}"
    puts 'Rode com CONFIRM=1 para gravar.' if dry_run
  end
end
