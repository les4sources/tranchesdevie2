# Prawn (génération des factures PDF, #38).
#
# Les factures utilisent la police interne Helvetica (AFM), suffisante pour le
# français (jeu Windows-1252 : accents, €, tiret cadratin). On masque
# l'avertissement m17n de Prawn, non pertinent pour notre contenu latin.
require "prawn"

Prawn::Fonts::AFM.hide_m17n_warning = true
