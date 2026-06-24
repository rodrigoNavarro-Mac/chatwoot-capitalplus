<script setup>
import { ref, computed } from 'vue';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import WhatsAppCampaignForm from 'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/WhatsAppCampaignForm.vue';

const props = defineProps({
  selectedCampaign: {
    type: Object,
    default: null,
  },
});

const { t } = useI18n();
const store = useStore();

const dialogRef = ref(null);
const whatsAppCampaignFormRef = ref(null);

const uiFlags = useMapGetter('campaigns/getUIFlags');
const isUpdatingCampaign = computed(() => uiFlags.value.isUpdating);

const isInvalidForm = computed(
  () => whatsAppCampaignFormRef.value?.isSubmitDisabled
);

const updateCampaign = async campaignDetails => {
  try {
    await store.dispatch('campaigns/update', {
      id: props.selectedCampaign.id,
      ...campaignDetails,
    });
    useAlert(t('CAMPAIGN.WHATSAPP_EDIT.FORM.API.SUCCESS_MESSAGE'));
    dialogRef.value.close();
  } catch (error) {
    const errorMessage =
      error?.response?.message ||
      t('CAMPAIGN.WHATSAPP_EDIT.FORM.API.ERROR_MESSAGE');
    useAlert(errorMessage);
  }
};

const handleSubmit = () => {
  updateCampaign(whatsAppCampaignFormRef.value.prepareCampaignDetails());
};

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    :title="t('CAMPAIGN.WHATSAPP_EDIT.TITLE')"
    :confirm-button-label="t('CAMPAIGN.WHATSAPP_EDIT.FORM.BUTTONS.UPDATE')"
    :cancel-button-label="t('CAMPAIGN.WHATSAPP_EDIT.FORM.BUTTONS.CANCEL')"
    :is-loading="isUpdatingCampaign"
    :disable-confirm-button="isUpdatingCampaign || isInvalidForm"
    overflow-y-auto
    @confirm="handleSubmit"
  >
    <WhatsAppCampaignForm
      ref="whatsAppCampaignFormRef"
      :selected-campaign="selectedCampaign"
    />
  </Dialog>
</template>
