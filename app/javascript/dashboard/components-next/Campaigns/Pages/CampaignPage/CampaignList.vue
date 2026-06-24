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

const emit = defineEmits(['edit', 'delete']);

const handleEdit = campaign => emit('edit', campaign);
const handleDelete = campaign => emit('delete', campaign);

const canEditCampaign = campaign => {
  const isWhatsApp = campaign.inbox?.channel_type === 'Channel::Whatsapp';
  const isEditable =
    campaign.campaign_status !== 'completed' &&
    campaign.campaign_status !== 'processing';
  return isWhatsApp && isEditable;
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
      :is-live-chat-type="isLiveChatType"
      :can-edit="canEditCampaign(campaign)"
      @edit="handleEdit(campaign)"
      @delete="handleDelete(campaign)"
    />
  </div>
</template>
