<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CadencesAPI from 'dashboard/api/cadences';
import Draggable from 'vuedraggable';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SpinnerLoader from 'dashboard/components-next/spinner/Spinner.vue';
import CadenceStepCard from './CadenceStepCard.vue';

const props = defineProps({
  cadenceDefinition: { type: Object, required: true },
  inboxId: { type: [Number, String], required: true },
});

const emit = defineEmits(['back']);

const { t } = useI18n();

const isLoading = ref(false);
const steps = ref([]);
const deleteTargetId = ref(null);
const showDeleteConfirmation = ref(false);

const fetchSteps = async () => {
  if (!props.cadenceDefinition?.id) return;
  isLoading.value = true;
  try {
    const { data } = await CadencesAPI.getStepDefinitions(
      props.cadenceDefinition.id
    );
    steps.value = data;
  } catch (error) {
    useAlert(t('CADENCE.TEMPLATES_SETTINGS.ERRORS.FETCH'));
  } finally {
    isLoading.value = false;
  }
};

const orderedSteps = computed({
  get: () => steps.value,
  set: async newOrder => {
    const previousOrder = steps.value;
    steps.value = newOrder;
    try {
      await CadencesAPI.reorderStepDefinitions(
        props.cadenceDefinition.id,
        newOrder.map(step => step.id)
      );
    } catch (error) {
      steps.value = previousOrder;
      useAlert(t('CADENCE.TEMPLATES_SETTINGS.ERRORS.REORDER'));
    }
  },
});

const addStep = async () => {
  try {
    const { data } = await CadencesAPI.createStepDefinition(
      props.cadenceDefinition.id,
      {
        template_name: t('CADENCE.TEMPLATES_SETTINGS.NEW_STEP_TEMPLATE_NAME'),
        template_language: 'es_MX',
        schedule_type: 'immediate',
        wait_window_minutes: 60,
        creates_call_task: false,
        active: true,
      }
    );
    steps.value = data;
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('CADENCE.TEMPLATES_SETTINGS.ERRORS.CREATE')
    );
  }
};

const saveStep = async (id, payload) => {
  try {
    const { data } = await CadencesAPI.updateStepDefinition(
      props.cadenceDefinition.id,
      id,
      payload
    );
    steps.value = data;
    useAlert(t('CADENCE.TEMPLATES_SETTINGS.SUCCESS'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('CADENCE.TEMPLATES_SETTINGS.ERRORS.SAVE')
    );
  }
};

const requestDeleteStep = id => {
  deleteTargetId.value = id;
  showDeleteConfirmation.value = true;
};

const closeDeleteConfirmation = () => {
  showDeleteConfirmation.value = false;
  deleteTargetId.value = null;
};

const confirmDeleteStep = async () => {
  const id = deleteTargetId.value;
  closeDeleteConfirmation();
  try {
    await CadencesAPI.deleteStepDefinition(props.cadenceDefinition.id, id);
    await fetchSteps();
    useAlert(t('CADENCE.TEMPLATES_SETTINGS.DELETE.SUCCESS'));
  } catch (error) {
    useAlert(t('CADENCE.TEMPLATES_SETTINGS.DELETE.ERROR'));
  }
};

onMounted(fetchSteps);
watch(() => props.cadenceDefinition?.id, fetchSteps);
</script>

<template>
  <div class="mx-6 max-w-4xl">
    <div class="flex flex-col gap-1 mb-4">
      <button
        type="button"
        class="flex items-center gap-1 text-sm text-n-slate-11 hover:text-n-slate-12 w-fit"
        @click="emit('back')"
      >
        <span class="i-lucide-arrow-left size-3.5" />
        {{ t('CADENCE.DEFINITIONS.BACK_TO_LIST') }}
      </button>
      <h3 class="text-heading-3 text-n-slate-12">
        {{ t('CADENCE.TEMPLATES_SETTINGS.TITLE') }} —
        {{ cadenceDefinition.name }}
      </h3>
      <p class="text-n-slate-11 text-body-2">
        {{ t('CADENCE.TEMPLATES_SETTINGS.DESCRIPTION') }}
      </p>
    </div>

    <div v-if="isLoading" class="flex justify-center py-8">
      <SpinnerLoader :size="28" />
    </div>

    <div v-else class="flex flex-col gap-4">
      <p v-if="!steps.length" class="text-n-slate-11 text-body-2">
        {{ t('CADENCE.TEMPLATES_SETTINGS.EMPTY') }}
      </p>

      <Draggable
        v-model="orderedSteps"
        item-key="id"
        handle=".cadence-step-drag-handle"
        animation="200"
        ghost-class="cadence-step-ghost"
        class="flex flex-col gap-4"
      >
        <template #item="{ element, index }">
          <CadenceStepCard
            :key="element.id"
            :step="element"
            :index="index"
            :inbox-id="inboxId"
            @save="payload => saveStep(element.id, payload)"
            @delete="requestDeleteStep(element.id)"
          />
        </template>
      </Draggable>

      <div class="w-full flex justify-start py-2">
        <NextButton
          type="button"
          ghost
          icon="i-lucide-plus"
          :label="t('CADENCE.TEMPLATES_SETTINGS.ADD_STEP')"
          @click="addStep"
        />
      </div>
    </div>

    <woot-delete-modal
      v-model:show="showDeleteConfirmation"
      :on-close="closeDeleteConfirmation"
      :on-confirm="confirmDeleteStep"
      :title="t('CADENCE.TEMPLATES_SETTINGS.DELETE.CONFIRM_TITLE')"
      :message="t('CADENCE.TEMPLATES_SETTINGS.DELETE.CONFIRM_MESSAGE')"
      :confirm-text="t('CADENCE.TEMPLATES_SETTINGS.DELETE.CONFIRM_YES')"
      :reject-text="t('CADENCE.TEMPLATES_SETTINGS.DELETE.CONFIRM_NO')"
    />
  </div>
</template>

<style scoped lang="scss">
.cadence-step-ghost {
  @apply opacity-50 bg-n-slate-3 dark:bg-n-slate-9;
}
</style>
