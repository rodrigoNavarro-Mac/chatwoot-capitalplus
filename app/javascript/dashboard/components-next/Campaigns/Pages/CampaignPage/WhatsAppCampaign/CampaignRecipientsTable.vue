<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { format } from 'date-fns';

import BaseTable from 'dashboard/components-next/table/BaseTable.vue';
import BaseTableRow from 'dashboard/components-next/table/BaseTableRow.vue';
import BaseTableCell from 'dashboard/components-next/table/BaseTableCell.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import CampaignRecipientStatusBadge from './CampaignRecipientStatusBadge.vue';

defineProps({
  recipients: {
    type: Array,
    default: () => [],
  },
  isFetching: {
    type: Boolean,
    default: false,
  },
  currentPage: {
    type: Number,
    default: 1,
  },
  totalItems: {
    type: Number,
    default: 0,
  },
  itemsPerPage: {
    type: Number,
    default: 25,
  },
});

const emit = defineEmits(['update:currentPage']);

const { t } = useI18n();

const headers = computed(() => [
  t('CAMPAIGN.WHATSAPP_RECIPIENTS.TABLE.HEADERS.NAME'),
  t('CAMPAIGN.WHATSAPP_RECIPIENTS.TABLE.HEADERS.STATUS'),
  t('CAMPAIGN.WHATSAPP_RECIPIENTS.TABLE.HEADERS.SENT_AT'),
  t('CAMPAIGN.WHATSAPP_RECIPIENTS.TABLE.HEADERS.DELIVERED_AT'),
  t('CAMPAIGN.WHATSAPP_RECIPIENTS.TABLE.HEADERS.READ_AT'),
  t('CAMPAIGN.WHATSAPP_RECIPIENTS.TABLE.HEADERS.FAILED_REASON'),
  t('CAMPAIGN.WHATSAPP_RECIPIENTS.TABLE.HEADERS.RESPONDED'),
]);

const displayName = recipient => recipient.name || recipient.phone_number;
const formatDate = value =>
  value ? format(new Date(value), 'LLL d, h:mm a') : '—';
</script>

<template>
  <div class="flex flex-col border rounded-xl border-n-weak">
    <div class="px-4">
      <BaseTable
        :headers="headers"
        :items="recipients"
        :loading="isFetching"
        :no-data-message="t('CAMPAIGN.WHATSAPP_RECIPIENTS.TABLE.EMPTY')"
      >
        <template #row="{ items }">
          <BaseTableRow
            v-for="recipient in items"
            :key="recipient.id"
            :item="recipient"
          >
            <BaseTableCell>
              <span class="font-medium text-n-slate-12">
                {{ displayName(recipient) }}
              </span>
              <span v-if="recipient.name" class="block text-xs text-n-slate-11">
                {{ recipient.phone_number }}
              </span>
            </BaseTableCell>
            <BaseTableCell>
              <CampaignRecipientStatusBadge :status="recipient.status" />
            </BaseTableCell>
            <BaseTableCell>{{ formatDate(recipient.sent_at) }}</BaseTableCell>
            <BaseTableCell>
              {{ formatDate(recipient.delivered_at) }}
            </BaseTableCell>
            <BaseTableCell>{{ formatDate(recipient.read_at) }}</BaseTableCell>
            <BaseTableCell>
              <span class="line-clamp-1">{{
                recipient.failed_reason || '—'
              }}</span>
            </BaseTableCell>
            <BaseTableCell>
              {{
                recipient.responded
                  ? t(
                      'CAMPAIGN.WHATSAPP_RECIPIENTS.FILTERS.RESPONDED.RESPONDED'
                    )
                  : '—'
              }}
            </BaseTableCell>
          </BaseTableRow>
        </template>
      </BaseTable>
    </div>
    <PaginationFooter
      v-if="totalItems"
      :current-page="currentPage"
      :total-items="totalItems"
      :items-per-page="itemsPerPage"
      @update:current-page="emit('update:currentPage', $event)"
    />
  </div>
</template>
