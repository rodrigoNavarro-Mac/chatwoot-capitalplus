<script setup>
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';
import AccountActionsAPI from 'dashboard/api/accountActions';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  currentChat: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['cancel', 'update:show']);

const store = useStore();
const { t } = useI18n();

const isFetching = ref(false);
const isMerging = ref(false);
const selectedConversationId = ref(null);

const localShow = computed({
  get: () => props.show,
  set: value => emit('update:show', value),
});

const contactId = computed(() => props.currentChat.meta?.sender?.id);

const otherConversations = computed(() => {
  const all = store.getters[
    'contactConversations/getAllConversationsByContactId'
  ](contactId.value);
  return all.filter(conversation => conversation.id !== props.currentChat.id);
});

onMounted(async () => {
  if (!contactId.value) return;
  isFetching.value = true;
  try {
    await store.dispatch('contactConversations/get', contactId.value);
  } finally {
    isFetching.value = false;
  }
});

const onCancel = () => {
  emit('cancel');
};

const onSubmit = async () => {
  if (!selectedConversationId.value) return;

  isMerging.value = true;
  try {
    const { data } = await AccountActionsAPI.mergeConversation(
      props.currentChat.id,
      selectedConversationId.value
    );
    store.dispatch('updateConversation', data);
    store.dispatch('removeMergedConversation', selectedConversationId.value);
    useAlert(t('CONVERSATION.MERGE.SUCCESS_MESSAGE'));
    onCancel();
  } catch (error) {
    useAlert(t('CONVERSATION.MERGE.ERROR_MESSAGE'));
  } finally {
    isMerging.value = false;
  }
};
</script>

<template>
  <woot-modal v-model:show="localShow" :on-close="onCancel">
    <div class="flex flex-col h-auto overflow-auto">
      <woot-modal-header
        :header-title="t('CONVERSATION.MERGE.TITLE')"
        :header-content="t('CONVERSATION.MERGE.DESCRIPTION')"
      />
      <form class="w-full px-8 pb-4" @submit.prevent="onSubmit">
        <div v-if="isFetching" class="py-4 text-sm text-n-slate-11">
          {{ t('CONVERSATION.MERGE.LOADING') }}
        </div>
        <div
          v-else-if="!otherConversations.length"
          class="py-4 text-sm text-n-slate-11"
        >
          {{ t('CONVERSATION.MERGE.EMPTY_STATE') }}
        </div>
        <ul v-else class="flex flex-col gap-2 my-2 list-none">
          <li
            v-for="conversation in otherConversations"
            :key="conversation.id"
            class="flex items-center gap-2 p-2 border rounded-lg cursor-pointer border-n-weak"
            @click="selectedConversationId = conversation.id"
          >
            <input
              :id="`merge-conversation-${conversation.id}`"
              v-model="selectedConversationId"
              type="radio"
              name="mergeeConversation"
              :value="conversation.id"
            />
            <label
              :for="`merge-conversation-${conversation.id}`"
              class="flex flex-col flex-1 cursor-pointer"
            >
              <span class="font-medium">#{{ conversation.id }}</span>
              <span class="text-sm text-n-slate-11">
                {{ conversation.status }} ·
                {{ dynamicTime(conversation.timestamp) }}
              </span>
            </label>
          </li>
        </ul>
        <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
          <NextButton
            faded
            slate
            type="reset"
            :label="t('CONVERSATION.MERGE.CANCEL')"
            @click.prevent="onCancel"
          />
          <NextButton
            type="submit"
            :label="t('CONVERSATION.MERGE.SUBMIT')"
            :disabled="!selectedConversationId || isMerging"
            :is-loading="isMerging"
          />
        </div>
      </form>
    </div>
  </woot-modal>
</template>
