#!/usr/bin/env ruby
# Script pour créer le prochain jour de cuisson
# Usage: rails runner lib/tasks/create_next_bake_day.rb

today = Date.current

# Trouver le prochain mardi (wday = 2) et vendredi (wday = 5)
next_tuesday = today + ((2 - today.wday) % 7).days
next_tuesday += 7.days if next_tuesday <= today

next_friday = today + ((5 - today.wday) % 7).days
next_friday += 7.days if next_friday <= today

# Choisir le plus proche
next_bake_day = [next_tuesday, next_friday].min

# Vérifier s'il existe déjà
if BakeDay.exists?(baked_on: next_bake_day)
  puts "⚠️  Le jour de cuisson du #{next_bake_day.strftime('%d/%m/%Y')} existe déjà."
  exit
end

# Calculer le cut_off_at
cut_off_at = BakeDay.calculate_cut_off_for(next_bake_day)

unless cut_off_at
  puts "❌ Erreur : La date #{next_bake_day.strftime('%d/%m/%Y')} n'est pas un mardi ou vendredi."
  exit 1
end

# Créer le jour de cuisson
bake_day = BakeDay.create!(
  baked_on: next_bake_day,
  cut_off_at: cut_off_at
)

puts "✅ Jour de cuisson créé :"
puts "   Date : #{bake_day.baked_on.strftime('%A %d/%m/%Y')}"
puts "   Cut-off : #{bake_day.cut_off_at.strftime('%d/%m/%Y à %H:%M')} (Europe/Brussels)"

