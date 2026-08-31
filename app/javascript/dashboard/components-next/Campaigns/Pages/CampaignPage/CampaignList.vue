<script setup>
import CampaignCard from 'dashboard/components-next/Campaigns/CampaignCard/CampaignCard.vue';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { useConfig } from 'dashboard/composables/useConfig';

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

const emit = defineEmits(['edit', 'delete', 'metrics', 'analytics']);
const ANALYTICS_CAMPAIGN_STATUSES = ['processing', 'completed'];
const { isEnterprise } = useConfig();

const handleEdit = campaign => emit('edit', campaign);
const handleDelete = campaign => emit('delete', campaign);
const handleMetrics = campaign => emit('metrics', campaign);
const handleAnalytics = campaign => emit('analytics', campaign);

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
      :show-analytics="
        isEnterprise &&
        campaign.inbox?.channel_type === INBOX_TYPES.WHATSAPP &&
        ANALYTICS_CAMPAIGN_STATUSES.includes(campaign.campaign_status)
      "
      @edit="handleEdit(campaign)"
      @delete="handleDelete(campaign)"
      @metrics="handleMetrics(campaign)"
      @analytics="handleAnalytics(campaign)"
    />
  </div>
</template>
