namespace :orders do
  desc "Resynchronise payment_status depuis les paiements RÉELS (#97). Corrige les " \
       "commandes marquées « payé » à tort. ATTENTION : réinitialise un marquage " \
       "manuel admin sans transaction — à lancer une fois, après déploiement."
  task resync_payment_status: :environment do
    corrected = 0
    Order.find_each do |order|
      before = order.payment_status
      order.recompute_payment_status!
      corrected += 1 if order.reload.payment_status != before
    end
    puts "payment_status resynchronisé depuis les paiements réels : #{corrected} commande(s) corrigée(s)."
  end

  desc "Liste les commandes affichées « payé » à tort : statut logistique avancé " \
       "(prête/récupérée/non-récupérée) sans paiement réel (#97)."
  task report_wrongly_paid: :environment do
    orders = Order.marked_paid_without_real_payment.includes(:customer)
    puts "#{orders.count} commande(s) potentiellement marquées « payé » à tort :"
    orders.find_each do |order|
      puts "  #{order.order_number} — #{order.customer.full_name} — " \
           "statut #{order.status} / paiement #{order.payment_status}"
    end
  end
end
