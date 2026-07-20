<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CadencesAPI from 'dashboard/api/cadences';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'shared/components/Spinner.vue';

const emit = defineEmits(['enrolled']);

const { t } = useI18n();

const ERROR_MESSAGE_KEYS = {
  already_enrolled: 'CADENCE.ENROLL_MODAL.ERRORS.ALREADY_ENROLLED',
  not_eligible: 'CADENCE.ENROLL_MODAL.ERRORS.NOT_ELIGIBLE',
  cadence_not_configured: 'CADENCE.ENROLL_MODAL.ERRORS.NOT_CONFIGURED',
};

const dialogRef = ref(null);
const query = ref('');
const conversations = ref([]);
const selectedConversationId = ref(null);
const isSearching = ref(false);
const isSubmitting = ref(false);
let searchTimeout = null;

const search = async () => {
  isSearching.value = true;
  try {
    const { data } = await CadencesAPI.eligibleConversations(query.value);
    conversations.value = data;
  } catch (error) {
    conversations.value = [];
  } finally {
    isSearching.value = false;
  }
};

watch(query, () => {
  clearTimeout(searchTimeout);
  searchTimeout = setTimeout(search, 300);
});

const open = () => {
  query.value = '';
  conversations.value = [];
  selectedConversationId.value = null;
  dialogRef.value?.open();
  search();
};

const close = () => dialogRef.value?.close();

const handleConfirm = async () => {
  if (!selectedConversationId.value) return;

  isSubmitting.value = true;
  try {
    const { data } = await CadencesAPI.enroll(selectedConversationId.value);
    useAlert(t('CADENCE.ENROLL_MODAL.SUCCESS'));
    emit('enrolled', data);
    close();
  } catch (error) {
    const reason = error?.response?.data?.error;
    useAlert(
      t(ERROR_MESSAGE_KEYS[reason] || 'CADENCE.ENROLL_MODAL.ERRORS.GENERIC')
    );
  } finally {
    isSubmitting.value = false;
  }
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    :title="t('CADENCE.ENROLL_MODAL.TITLE')"
    :description="t('CADENCE.ENROLL_MODAL.DESCRIPTION')"
    :confirm-button-label="t('CADENCE.ENROLL_MODAL.CONFIRM')"
    :cancel-button-label="t('CADENCE.ENROLL_MODAL.CANCEL')"
    :disable-confirm-button="!selectedConversationId"
    :is-loading="isSubmitting"
    @confirm="handleConfirm"
  >
    <div class="flex flex-col gap-3">
      <input
        v-model="query"
        type="text"
        class="!mb-0"
        :placeholder="t('CADENCE.ENROLL_MODAL.SEARCH_PLACEHOLDER')"
      />
      <div v-if="isSearching" class="flex justify-center py-4">
        <Spinner />
      </div>
      <div
        v-else-if="!conversations.length"
        class="text-sm text-n-slate-11 py-4 text-center"
      >
        {{ t('CADENCE.ENROLL_MODAL.EMPTY') }}
      </div>
      <ul v-else class="flex flex-col gap-1 max-h-64 overflow-y-auto">
        <li v-for="conversation in conversations" :key="conversation.id">
          <label
            class="flex items-center gap-2 p-2 rounded-lg cursor-pointer hover:bg-n-slate-3"
            :class="
              selectedConversationId === conversation.id ? 'bg-n-slate-3' : ''
            "
          >
            <input
              v-model="selectedConversationId"
              type="radio"
              name="eligible-conversation"
              :value="conversation.id"
            />
            <div class="flex flex-col">
              <span class="text-sm text-n-slate-12">
                {{
                  conversation.contact.name || conversation.contact.phone_number
                }}
                <span class="text-n-slate-11"
                  >#{{ conversation.display_id }}</span
                >
              </span>
              <span class="text-xs text-n-slate-11">
                {{ conversation.inbox.name }} · {{ conversation.assignee.name }}
              </span>
            </div>
          </label>
        </li>
      </ul>
    </div>
  </Dialog>
</template>
