# Solo datos (no cambia el schema) -- remapea los `stage` ya guardados en sales_funnel_goals a los
# nombres canónicos que ahora usa SalesFunnelGoal::STAGES, desde la unificación de los 3 embudos de
# ventas (ver V2::Reports::SalesFunnelBuilder): leads->lead_created, customer_replied->
# lead_contacted, has_deal->deal_created, visita_efectiva->visit_effective, closed_won sin cambio.
# Reversible para poder hacer rollback sin perder las metas ya capturadas por el equipo.
class RenameSalesFunnelGoalStages < ActiveRecord::Migration[7.1]
  MAPPING = {
    'leads' => 'lead_created',
    'customer_replied' => 'lead_contacted',
    'has_deal' => 'deal_created',
    'visita_efectiva' => 'visit_effective'
  }.freeze

  def up
    MAPPING.each do |old_stage, new_stage|
      execute "UPDATE sales_funnel_goals SET stage = #{quote(new_stage)} WHERE stage = #{quote(old_stage)}"
    end
  end

  def down
    MAPPING.each do |old_stage, new_stage|
      execute "UPDATE sales_funnel_goals SET stage = #{quote(old_stage)} WHERE stage = #{quote(new_stage)}"
    end
  end
end
