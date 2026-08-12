<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Input from 'dashboard/components-next/input/Input.vue';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';

const props = defineProps({
  searchValue: {
    type: String,
    default: '',
  },
  statusFilter: {
    type: String,
    default: '',
  },
  respondedFilter: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['search', 'update:status', 'update:responded']);

const { t } = useI18n();

const statusOptions = computed(() => [
  {
    id: 'queued',
    name: t('CAMPAIGN.WHATSAPP_RECIPIENTS.FILTERS.STATUS.QUEUED'),
  },
  { id: 'sent', name: t('CAMPAIGN.WHATSAPP_RECIPIENTS.FILTERS.STATUS.SENT') },
  {
    id: 'delivered',
    name: t('CAMPAIGN.WHATSAPP_RECIPIENTS.FILTERS.STATUS.DELIVERED'),
  },
  { id: 'read', name: t('CAMPAIGN.WHATSAPP_RECIPIENTS.FILTERS.STATUS.READ') },
  {
    id: 'failed',
    name: t('CAMPAIGN.WHATSAPP_RECIPIENTS.FILTERS.STATUS.FAILED'),
  },
]);

const respondedOptions = computed(() => [
  {
    id: 'true',
    name: t('CAMPAIGN.WHATSAPP_RECIPIENTS.FILTERS.RESPONDED.RESPONDED'),
  },
  {
    id: 'false',
    name: t('CAMPAIGN.WHATSAPP_RECIPIENTS.FILTERS.RESPONDED.NOT_RESPONDED'),
  },
]);

const selectedStatus = computed({
  get: () =>
    statusOptions.value.find(option => option.id === props.statusFilter) ||
    null,
  set: value => emit('update:status', value?.id || ''),
});

const selectedResponded = computed({
  get: () =>
    respondedOptions.value.find(
      option => option.id === props.respondedFilter
    ) || null,
  set: value => emit('update:responded', value?.id || ''),
});
</script>

<template>
  <div class="flex flex-wrap items-center gap-2">
    <Input
      class="flex-1 min-w-[12rem]"
      type="search"
      size="sm"
      :model-value="searchValue"
      :placeholder="t('CAMPAIGN.WHATSAPP_RECIPIENTS.SEARCH_PLACEHOLDER')"
      @update:model-value="emit('search', $event)"
    />
    <SingleSelect
      v-model="selectedStatus"
      disable-search
      placeholder-icon="i-lucide-filter"
      :placeholder="t('CAMPAIGN.WHATSAPP_RECIPIENTS.FILTERS.STATUS.LABEL')"
      :options="statusOptions"
    />
    <SingleSelect
      v-model="selectedResponded"
      disable-search
      placeholder-icon="i-lucide-reply"
      :placeholder="t('CAMPAIGN.WHATSAPP_RECIPIENTS.FILTERS.RESPONDED.LABEL')"
      :options="respondedOptions"
    />
  </div>
</template>
