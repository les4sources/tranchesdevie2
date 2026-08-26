import { Controller } from "@hotwired/stimulus"
import { parsePhoneNumber, AsYouType, getCountryCallingCode } from "libphonenumber-js"

export default class extends Controller {
  static targets = ["input", "flag"]

  static values = {
    defaultCountry: { type: String, default: "BE" }
  }

  connect() {
    this.currentCountry = this.defaultCountryValue
    this.flagEmojis = this.getFlagEmojis()
    this.countries = this.getAllCountries()

    // Le champ accepte un GSM OU un e-mail : on n'affiche le drapeau et on ne
    // formate que tant que la saisie ressemble à un numéro.
    this.syncFlagVisibility()

    this.inputTarget.addEventListener("input", this.handleInput.bind(this))
    this.inputTarget.addEventListener("blur", this.handleBlur.bind(this))
  }

  // Une saisie contenant une lettre ou un "@" est traitée comme un e-mail :
  // on ne lui applique ni formatage téléphonique ni préfixe pays.
  looksLikeEmail(value) {
    return /[A-Za-z@]/.test(value || "")
  }

  handleInput(event) {
    const value = event.target.value

    this.syncFlagVisibility()
    if (this.looksLikeEmail(value)) return

    // Détecter si l'utilisateur a changé le code pays
    if (value.startsWith("+")) {
      const detectedCountry = this.detectCountryFromInput(value)
      if (detectedCountry && detectedCountry !== this.currentCountry) {
        this.currentCountry = detectedCountry
        this.updateFlag()
      }
    }

    // Formater en temps réel (uniquement pour les numéros)
    this.formatPhoneNumber(value)
  }

  handleBlur() {
    // S'assurer que le numéro est en format E.164 (jamais pour un e-mail)
    const value = this.inputTarget.value
    if (value && !this.looksLikeEmail(value)) {
      try {
        const phoneNumber = parsePhoneNumber(value, this.currentCountry)
        if (phoneNumber.isValid()) {
          this.inputTarget.value = phoneNumber.format("E.164")
        }
      } catch (e) {
        // Ignorer les erreurs de parsing
      }
    }
  }

  // Masque le drapeau quand la saisie ressemble à un e-mail, l'affiche sinon.
  syncFlagVisibility() {
    if (!this.hasFlagTarget) return
    this.flagTarget.style.display = this.looksLikeEmail(this.inputTarget.value) ? "none" : ""
  }

  detectCountryFromInput(value) {
    if (!value || !value.startsWith("+")) return null
    
    try {
      // Essayer de parser le numéro pour détecter automatiquement le pays
      const phoneNumber = parsePhoneNumber(value)
      if (phoneNumber && phoneNumber.country) {
        return phoneNumber.country
      }
    } catch (e) {
      // Si le parsing échoue, essayer de détecter par le code d'appel
      const match = value.match(/^\+(\d{1,3})/)
      if (!match) return null
      
      const callingCode = match[1]
      
      // Trouver le pays correspondant au code (prendre le premier trouvé)
      for (const country of this.countries) {
        try {
          const code = getCountryCallingCode(country)
          if (code === callingCode) {
            return country
          }
        } catch (e) {
          continue
        }
      }
    }
    
    return null
  }

  formatPhoneNumber(value) {
    if (!value || !value.startsWith("+")) {
      return
    }

    try {
      const cursorPosition = this.inputTarget.selectionStart || value.length
      
      // Extraire uniquement les chiffres avant le curseur (sans le +)
      const beforeCursor = value.substring(0, cursorPosition)
      const digitsBeforeCursor = beforeCursor.replace(/\D/g, '').length
      
      const formatter = new AsYouType(this.currentCountry)
      const formatted = formatter.input(value)
      
      // Ne mettre à jour que si le formatage a changé quelque chose
      if (formatted !== value) {
        // Trouver la nouvelle position du curseur en comptant les chiffres (sans compter le +)
        let newPosition = formatted.length
        let digitCount = 0
        
        // Parcourir la valeur formatée et compter les chiffres
        for (let i = 0; i < formatted.length; i++) {
          const char = formatted[i]
          
          // Ignorer le + au début
          if (char === '+') {
            continue
          }
          
          // Compter les chiffres
          if (/\d/.test(char)) {
            digitCount++
            // Si on a atteint le nombre de chiffres qu'on avait avant le curseur
            if (digitCount === digitsBeforeCursor) {
              // Placer le curseur juste après ce chiffre
              newPosition = i + 1
              break
            }
          }
        }
        
        // Si on est à la fin de la saisie, mettre le curseur à la fin
        if (digitsBeforeCursor === 0 || digitCount < digitsBeforeCursor) {
          newPosition = formatted.length
        }
        
        this.inputTarget.value = formatted
        
        // Utiliser setTimeout pour s'assurer que le DOM est mis à jour avant de repositionner le curseur
        setTimeout(() => {
          this.inputTarget.setSelectionRange(newPosition, newPosition)
        }, 0)
      }
    } catch (e) {
      // Si le formatage échoue, laisser l'utilisateur continuer à taper
    }
  }

  updateFlag() {
    const emoji = this.flagEmojis[this.currentCountry] || "🌐"
    this.flagTarget.textContent = emoji
  }

  getAllCountries() {
    // Liste de tous les codes pays ISO 3166-1 alpha-2 supportés par libphonenumber-js
    return [
      "AD", "AE", "AF", "AG", "AI", "AL", "AM", "AO", "AQ", "AR", "AS", "AT",
      "AU", "AW", "AX", "AZ", "BA", "BB", "BD", "BE", "BF", "BG", "BH", "BI",
      "BJ", "BL", "BM", "BN", "BO", "BQ", "BR", "BS", "BT", "BV", "BW", "BY",
      "BZ", "CA", "CC", "CD", "CF", "CG", "CH", "CI", "CK", "CL", "CM", "CN",
      "CO", "CR", "CU", "CV", "CW", "CX", "CY", "CZ", "DE", "DJ", "DK", "DM",
      "DO", "DZ", "EC", "EE", "EG", "EH", "ER", "ES", "ET", "FI", "FJ", "FK",
      "FM", "FO", "FR", "GA", "GB", "GD", "GE", "GF", "GG", "GH", "GI", "GL",
      "GM", "GN", "GP", "GQ", "GR", "GS", "GT", "GU", "GW", "GY", "HK", "HM",
      "HN", "HR", "HT", "HU", "ID", "IE", "IL", "IM", "IN", "IO", "IQ", "IR",
      "IS", "IT", "JE", "JM", "JO", "JP", "KE", "KG", "KH", "KI", "KM", "KN",
      "KP", "KR", "KW", "KY", "KZ", "LA", "LB", "LC", "LI", "LK", "LR", "LS",
      "LT", "LU", "LV", "LY", "MA", "MC", "MD", "ME", "MF", "MG", "MH", "MK",
      "ML", "MM", "MN", "MO", "MP", "MQ", "MR", "MS", "MT", "MU", "MV", "MW",
      "MX", "MY", "MZ", "NA", "NC", "NE", "NF", "NG", "NI", "NL", "NO", "NP",
      "NR", "NU", "NZ", "OM", "PA", "PE", "PF", "PG", "PH", "PK", "PL", "PM",
      "PN", "PR", "PS", "PT", "PW", "PY", "QA", "RE", "RO", "RS", "RU", "RW",
      "SA", "SB", "SC", "SD", "SE", "SG", "SH", "SI", "SJ", "SK", "SL", "SM",
      "SN", "SO", "SR", "SS", "ST", "SV", "SX", "SY", "SZ", "TC", "TD", "TF",
      "TG", "TH", "TJ", "TK", "TL", "TM", "TN", "TO", "TR", "TT", "TV", "TW",
      "TZ", "UA", "UG", "UM", "US", "UY", "UZ", "VA", "VC", "VE", "VG", "VI",
      "VN", "VU", "WF", "WS", "XK", "YE", "YT", "ZA", "ZM", "ZW"
    ]
  }

  getFlagEmojis() {
    return {
      AD: "🇦🇩", AE: "🇦🇪", AF: "🇦🇫", AG: "🇦🇬", AI: "🇦🇮", AL: "🇦🇱",
      AM: "🇦🇲", AO: "🇦🇴", AQ: "🇦🇶", AR: "🇦🇷", AS: "🇦🇸", AT: "🇦🇹",
      AU: "🇦🇺", AW: "🇦🇼", AX: "🇦🇽", AZ: "🇦🇿", BA: "🇧🇦", BB: "🇧🇧",
      BD: "🇧🇩", BE: "🇧🇪", BF: "🇧🇫", BG: "🇧🇬", BH: "🇧🇭", BI: "🇧🇮",
      BJ: "🇧🇯", BL: "🇧🇱", BM: "🇧🇲", BN: "🇧🇳", BO: "🇧🇴", BQ: "🇧🇶",
      BR: "🇧🇷", BS: "🇧🇸", BT: "🇧🇹", BV: "🇧🇻", BW: "🇧🇼", BY: "🇧🇾",
      BZ: "🇧🇿", CA: "🇨🇦", CC: "🇨🇨", CD: "🇨🇩", CF: "🇨🇫", CG: "🇨🇬",
      CH: "🇨🇭", CI: "🇨🇮", CK: "🇨🇰", CL: "🇨🇱", CM: "🇨🇲", CN: "🇨🇳",
      CO: "🇨🇴", CR: "🇨🇷", CU: "🇨🇺", CV: "🇨🇻", CW: "🇨🇼", CX: "🇨🇽",
      CY: "🇨🇾", CZ: "🇨🇿", DE: "🇩🇪", DJ: "🇩🇯", DK: "🇩🇰", DM: "🇩🇲",
      DO: "🇩🇴", DZ: "🇩🇿", EC: "🇪🇨", EE: "🇪🇪", EG: "🇪🇬", EH: "🇪🇭",
      ER: "🇪🇷", ES: "🇪🇸", ET: "🇪🇹", FI: "🇫🇮", FJ: "🇫🇯", FK: "🇫🇰",
      FM: "🇫🇲", FO: "🇫🇴", FR: "🇫🇷", GA: "🇬🇦", GB: "🇬🇧", GD: "🇬🇩",
      GE: "🇬🇪", GF: "🇬🇫", GG: "🇬🇬", GH: "🇬🇭", GI: "🇬🇮", GL: "🇬🇱",
      GM: "🇬🇲", GN: "🇬🇳", GP: "🇬🇵", GQ: "🇬🇶", GR: "🇬🇷", GS: "🇬🇸",
      GT: "🇬🇹", GU: "🇬🇺", GW: "🇬🇼", GY: "🇬🇾", HK: "🇭🇰", HM: "🇭🇲",
      HN: "🇭🇳", HR: "🇭🇷", HT: "🇭🇹", HU: "🇭🇺", ID: "🇮🇩", IE: "🇮🇪",
      IL: "🇮🇱", IM: "🇮🇲", IN: "🇮🇳", IO: "🇮🇴", IQ: "🇮🇶", IR: "🇮🇷",
      IS: "🇮🇸", IT: "🇮🇹", JE: "🇯🇪", JM: "🇯🇲", JO: "🇯🇴", JP: "🇯🇵",
      KE: "🇰🇪", KG: "🇰🇬", KH: "🇰🇭", KI: "🇰🇮", KM: "🇰🇲", KN: "🇰🇳",
      KP: "🇰🇵", KR: "🇰🇷", KW: "🇰🇼", KY: "🇰🇾", KZ: "🇰🇿", LA: "🇱🇦",
      LB: "🇱🇧", LC: "🇱🇨", LI: "🇱🇮", LK: "🇱🇰", LR: "🇱🇷", LS: "🇱🇸",
      LT: "🇱🇹", LU: "🇱🇺", LV: "🇱🇻", LY: "🇱🇾", MA: "🇲🇦", MC: "🇲🇨",
      MD: "🇲🇩", ME: "🇲🇪", MF: "🇲🇫", MG: "🇲🇬", MH: "🇲🇭", MK: "🇲🇰",
      ML: "🇲🇱", MM: "🇲🇲", MN: "🇲🇳", MO: "🇲🇴", MP: "🇲🇵", MQ: "🇲🇶",
      MR: "🇲🇷", MS: "🇲🇸", MT: "🇲🇹", MU: "🇲🇺", MV: "🇲🇻", MW: "🇲🇼",
      MX: "🇲🇽", MY: "🇲🇾", MZ: "🇲🇿", NA: "🇳🇦", NC: "🇳🇨", NE: "🇳🇪",
      NF: "🇳🇫", NG: "🇳🇬", NI: "🇳🇮", NL: "🇳🇱", NO: "🇳🇴", NP: "🇳🇵",
      NR: "🇳🇷", NU: "🇳🇺", NZ: "🇳🇿", OM: "🇴🇲", PA: "🇵🇦", PE: "🇵🇪",
      PF: "🇵🇫", PG: "🇵🇬", PH: "🇵🇭", PK: "🇵🇰", PL: "🇵🇱", PM: "🇵🇲",
      PN: "🇵🇳", PR: "🇵🇷", PS: "🇵🇸", PT: "🇵🇹", PW: "🇵🇼", PY: "🇵🇾",
      QA: "🇶🇦", RE: "🇷🇪", RO: "🇷🇴", RS: "🇷🇸", RU: "🇷🇺", RW: "🇷🇼",
      SA: "🇸🇦", SB: "🇸🇧", SC: "🇸🇨", SD: "🇸🇩", SE: "🇸🇪", SG: "🇸🇬",
      SH: "🇸🇭", SI: "🇸🇮", SJ: "🇸🇯", SK: "🇸🇰", SL: "🇸🇱", SM: "🇸🇲",
      SN: "🇸🇳", SO: "🇸🇴", SR: "🇸🇷", SS: "🇸🇸", ST: "🇸🇹", SV: "🇸🇻",
      SX: "🇸🇽", SY: "🇸🇾", SZ: "🇸🇿", TC: "🇹🇨", TD: "🇹🇩", TF: "🇹🇫",
      TG: "🇹🇬", TH: "🇹🇭", TJ: "🇹🇯", TK: "🇹🇰", TL: "🇹🇱", TM: "🇹🇲",
      TN: "🇹🇳", TO: "🇹🇴", TR: "🇹🇷", TT: "🇹🇹", TV: "🇹🇻", TW: "🇹🇼",
      TZ: "🇹🇿", UA: "🇺🇦", UG: "🇺🇬", UM: "🇺🇲", US: "🇺🇸", UY: "🇺🇾",
      UZ: "🇺🇿", VA: "🇻🇦", VC: "🇻🇨", VE: "🇻🇪", VG: "🇻🇬", VI: "🇻🇮",
      VN: "🇻🇳", VU: "🇻🇺", WF: "🇼🇫", WS: "🇼🇸", XK: "🇽🇰", YE: "🇾🇪",
      YT: "🇾🇹", ZA: "🇿🇦", ZM: "🇿🇲", ZW: "🇿🇼"
    }
  }
}

