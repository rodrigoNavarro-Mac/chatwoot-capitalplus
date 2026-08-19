<script setup>
import CampaignCard from 'dashboard/components-next/Campaigns/CampaignCard/CampaignCard.vue';

defineProps({
  campaigns: {
    type: Array,
    required: true,
  },
  isLiveChatType: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['edit', 'delete', 'metrics']);

const handleEdit = campaign => emit('edit', campaign);
const handleDelete = campaign => emit('delete', campaign);
const handleMetrics = campaign => emit('metrics', campaign);

const isWhatsAppCampaign = campaign =>
  campaign.inbox?.channel_type === 'Channel::Whatsapp';

const canEditCampaign = campaign => {
  const isEditable =
    campaign.campaign_status !== 'completed' &&
    campaign.campaign_status !== 'processing';
  return isWhatsAppCampaign(campaign) && isEditable;
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <CampaignCard
      v-for="campaign in campaigns"
      :key="campaign.id"
      :title="campaign.title"
      :message="campaign.message"
      :is-enabled="campaign.enabled"
      :status="campaign.campaign_status"
      :sender="campaign.sender"
      :inbox="campaign.inbox"
      :scheduled-at="campaign.scheduled_at"
      :remaining="campaign.remaining"
      :is-live-chat-type="isLiveChatType"
      :can-edit="canEditCampaign(campaign)"
      :can-view-metrics="isWhatsAppCampaign(campaign)"
      @edit="handleEdit(campaign)"
      @delete="handleDelete(campaign)"
      @metrics="handleMetrics(campaign)"
    />
  </div>
</template>
