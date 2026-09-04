require 'rails_helper'

RSpec.describe OrderMailer, type: :mailer do
  let(:customer) { create(:customer, first_name: "Marc", email: "marc@example.com") }
  let(:bake_day) { create(:bake_day, :can_order) }
  let(:order) { create(:order, :with_items, customer: customer, bake_day: bake_day) }

  describe '#confirmation' do
    subject(:mail) { described_class.confirmation(order) }

    it 'is addressed to the customer email' do
      expect(mail.to).to eq([ "marc@example.com" ])
    end

    it 'references the order number in the subject and body' do
      expect(mail.subject).to include(order.order_number)
      expect(mail.body.encoded).to include(order.order_number)
    end

    it 'lists the ordered items' do
      order.order_items.each do |item|
        expect(mail.body.encoded).to include(item.product_variant.product.name)
      end
    end

    it 'tags the email kind and order id' do
      expect(mail["X-Email-Kind"].value).to eq("confirmation")
      expect(mail["X-Order-Id"].value).to eq(order.id.to_s)
    end

    it 'includes a working unsubscribe (preferences) link' do
      html = mail.html_part.body.decoded
      expect(html).to include("/e-mails/preferences/")
      token = html[%r{/e-mails/preferences/([^"\s]+)}, 1]
      expect(Customer.find_signed(token, purpose: :email_unsubscribe)).to eq(customer)
    end

    it 'logs an EmailMessage when delivered' do
      expect { mail.deliver_now }.to change(EmailMessage, :count).by(1)
      expect(EmailMessage.last).to have_attributes(kind: "confirmation", order_id: order.id, customer_id: customer.id)
    end

    # Où et quand venir (#252) — dans les DEUX parties, HTML et texte.
    describe 'le bloc de retrait' do
      let(:instructions) { "Le jour de la cuisson, à partir de 18h." }

      # Le lieu doit être ouvert sur la fournée, sinon la commande est refusée.
      def attach(location)
        bake_day.pickup_location_ids = (bake_day.pickup_location_ids + [ location.id ]).uniq
        bake_day.save!
        order.update!(pickup_location: location)
      end

      it "nomme le lieu et reprend ses instructions" do
        location = create(:pickup_location, name: "Marché d'Anhée", pickup_instructions: instructions)
        attach(location)

        expect(mail.html_part.body.decoded).to include("Marché d'Anhée").or include(CGI.escapeHTML("Marché d'Anhée"))
        expect(mail.html_part.body.decoded).to include(instructions)
        expect(mail.text_part.body.decoded).to include("Marché d'Anhée")
        expect(mail.text_part.body.decoded).to include(instructions)
      end

      it "n'affiche aucune instruction quand le lieu n'en porte pas" do
        location = create(:pickup_location, name: "Marché de Dinant", pickup_instructions: nil)
        attach(location)

        expect(mail.text_part.body.decoded).to include("Marché de Dinant")
        expect(mail.text_part.body.decoded).not_to include(instructions)
        expect(mail.html_part.body.decoded).not_to include(instructions)
      end

      it "n'annonce plus l'adresse de l'épicerie à qui a choisi le marché" do
        location = create(:pickup_location, name: "Marché d'Anhée", pickup_instructions: instructions)
        attach(location)

        expect(mail.text_part.body.decoded).not_to include("Fonds d'Ahinvaux")
      end

      it "garde une phrase de repli quand le lieu n'a pas d'instructions" do
        location = create(:pickup_location, name: "Marché de Namur", pickup_instructions: nil)
        attach(location)

        expect(mail.text_part.body.decoded).to include("Ta commande t'attendra le jour de cuisson")
      end
    end
  end
end
