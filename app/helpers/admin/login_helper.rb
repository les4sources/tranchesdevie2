module Admin::LoginHelper
  # Salut et sous-titre selon l'heure à Bruxelles : la page de connexion
  # parle au boulanger au moment où il arrive au fournil.
  def admin_login_greeting(now = Time.current.in_time_zone("Europe/Brussels"))
    case now.hour
    when 5..11  then [ "Bonjour", "Le four chauffe, la pâte attend tes mains." ]
    when 12..17 then [ "Bon après-midi", "Le levain prend son temps. Toi aussi." ]
    when 18..22 then [ "Bonsoir", "Les commandes de la prochaine fournée se dessinent." ]
    else             [ "Bonne nuit", "Le levain veille. Le fournil aussi." ]
    end
  end

  def admin_login_next_bake(bake_day)
    return unless bake_day

    I18n.l(bake_day.baked_on, format: "%A %-d %B")
  end
end
