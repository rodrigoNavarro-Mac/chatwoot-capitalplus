<script setup>
import { ref, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CadencesAPI from 'dashboard/api/cadences';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SpinnerLoader from 'dashboard/components-next/spinner/Spinner.vue';
import CadenceTemplatesPage from './CadenceTemplatesPage.vue';

const props = defineProps({
  inbox: { type: Object, required: true },
});

const { t } = useI18n();

const isLoading = ref(false);
const definitions = ref([]);
const selectedDefinition = ref(null);
const isAdding = ref(false);
const newDefinition = ref({ name: '', segment_value: '', is_default: false });
const deleteTargetId = ref(null);
const showDeleteConfirmation = ref(false);

const fetchDefinitions = async () => {
  if (!props.inbox?.id) return;
  isLoading.value = true;
  try {
    const { data } = await CadencesAPI.getCadenceDefinitions(props.inbox.id);
    definitions.value = data;
  } catch (error) {
    useAlert(t('CADENCE.DEFINITIONS.ERRORS.FETCH'));
  } finally {
    isLoading.value = false;
  }
};

const openAddForm = () => {
  newDefinition.value = { name: '', segment_value: '', is_default: false };
  isAdding.value = true;
};

const cancelAdd = () => {
  isAdding.value = false;
};

const createDefinition = async () => {
  if (!newDefinition.value.name?.trim()) {
    useAlert(t('CADENCE.DEFINITIONS.ERRORS.NAME_REQUIRED'));
    return;
  }
  try {
    const { data } = await CadencesAPI.createCadenceDefinition(
      props.inbox.id,
      newDefinition.value
    );
    definitions.value = data;
    isAdding.value = false;
    useAlert(t('CADENCE.DEFINITIONS.SUCCESS_CREATE'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message || t('CADENCE.DEFINITIONS.ERRORS.CREATE')
    );
  }
};

const toggleActive = async definition => {
  try {
    const { data } = await CadencesAPI.updateCadenceDefinition(definition.id, {
      active: !definition.active,
    });
    definitions.value = data;
  } catch (error) {
    useAlert(t('CADENCE.DEFINITIONS.ERRORS.SAVE'));
  }
};

const markAsDefault = async definition => {
  try {
    const { data } = await CadencesAPI.updateCadenceDefinition(definition.id, {
      is_default: true,
    });
    definitions.value = data;
    useAlert(t('CADENCE.DEFINITIONS.SUCCESS_DEFAULT'));
  } catch (error) {
    useAlert(t('CADENCE.DEFINITIONS.ERRORS.SAVE'));
  }
};

const requestDelete = id => {
  deleteTargetId.value = id;
  showDeleteConfirmation.value = true;
};

const closeDeleteConfirmation = () => {
  showDeleteConfirmation.value = false;
  deleteTargetId.value = null;
};

const confirmDelete = async () => {
  const id = deleteTargetId.value;
  closeDeleteConfirmation();
  try {
    await CadencesAPI.deleteCadenceDefinition(id);
    await fetchDefinitions();
    useAlert(t('CADENCE.DEFINITIONS.SUCCESS_DELETE'));
  } catch (error) {
    useAlert(t('CADENCE.DEFINITIONS.ERRORS.DELETE'));
  }
};

const openSteps = definition => {
  selectedDefinition.value = definition;
};

const backToList = () => {
  selectedDefinition.value = null;
  fetchDefinitions();
};

onMounted(fetchDefinitions);
watch(() => props.inbox?.id, fetchDefinitions);
</script>

<template>
  <CadenceTemplatesPage
    v-if="selectedDefinition"
    :cadence-definition="selectedDefinition"
    @back="backToList"
  />
  <div v-else class="mx-6 max-w-4xl">
    <div class="flex flex-col gap-1 mb-4">
      <h3 class="text-heading-3 text-n-slate-12">
        {{ t('CADENCE.DEFINITIONS.TITLE') }}
      </h3>
      <p class="text-n-slate-11 text-body-2">
        {{ t('CADENCE.DEFINITIONS.DESCRIPTION') }}
      </p>
    </div>

    <div v-if="isLoading" class="flex justify-center py-8">
      <SpinnerLoader :size="28" />
    </div>

    <div v-else class="flex flex-col gap-4">
      <p v-if="!definitions.length" class="text-n-slate-11 text-body-2">
        {{ t('CADENCE.DEFINITIONS.EMPTY') }}
      </p>

      <div
        v-for="definition in definitions"
        :key="definition.id"
        class="flex items-center justify-between gap-3 p-4 rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
      >
        <div class="flex flex-col gap-1">
          <div class="flex items-center gap-2">
            <span class="text-heading-3 text-n-slate-12">{{
              definition.name
            }}</span>
            <span
              v-if="definition.is_default"
              class="px-2 py-0.5 rounded-full text-xs bg-n-blue-9/10 text-n-blue-11"
            >
              {{ t('CADENCE.DEFINITIONS.DEFAULT_BADGE') }}
            </span>
            <span
              v-if="!definition.active"
              class="px-2 py-0.5 rounded-full text-xs bg-n-slate-9/10 text-n-slate-11"
            >
              {{ t('CADENCE.DEFINITIONS.INACTIVE_BADGE') }}
            </span>
          </div>
          <span class="text-sm text-n-slate-11">
            {{
              definition.segment_value
                ? t('CADENCE.DEFINITIONS.SEGMENT_LABEL', {
                    value: definition.segment_value,
                  })
                : t('CADENCE.DEFINITIONS.NO_SEGMENT')
            }}
          </span>
          <span class="text-xs text-n-slate-10">
            {{
              t('CADENCE.DEFINITIONS.STEPS_COUNT', {
                count: definition.steps_count,
              })
            }}
            ·
            {{
              t('CADENCE.DEFINITIONS.ENROLLMENTS_COUNT', {
                count: definition.enrollments_count,
              })
            }}
          </span>
        </div>
        <div class="flex items-center gap-2 flex-shrink-0">
          <NextButton
            v-if="!definition.is_default"
            type="button"
            faded
            slate
            xs
            :label="t('CADENCE.DEFINITIONS.MARK_DEFAULT')"
            @click="markAsDefault(definition)"
          />
          <label class="flex items-center gap-2 text-sm text-n-slate-11">
            {{ t('CADENCE.DEFINITIONS.ACTIVE') }}
            <Switch
              :model-value="definition.active"
              @update:model-value="() => toggleActive(definition)"
            />
          </label>
          <NextButton
            type="button"
            :label="t('CADENCE.DEFINITIONS.MANAGE_STEPS')"
            @click="openSteps(definition)"
          />
          <NextButton
            type="button"
            ghost
            ruby
            xs
            icon="i-lucide-trash-2"
            :label="t('CADENCE.DEFINITIONS.DELETE.BUTTON')"
            @click="requestDelete(definition.id)"
          />
        </div>
      </div>

      <div
        v-if="isAdding"
        class="flex flex-col gap-3 p-4 rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
      >
        <Input
          v-model="newDefinition.name"
          :label="t('CADENCE.DEFINITIONS.NAME')"
          :placeholder="t('CADENCE.DEFINITIONS.NAME_PLACEHOLDER')"
        />
        <Input
          v-model="newDefinition.segment_value"
          :label="t('CADENCE.DEFINITIONS.SEGMENT_INPUT_LABEL')"
          :placeholder="t('CADENCE.DEFINITIONS.SEGMENT_PLACEHOLDER')"
        />
        <label class="flex items-center gap-2 text-sm text-n-slate-11">
          <Switch v-model="newDefinition.is_default" />
          {{ t('CADENCE.DEFINITIONS.MARK_AS_DEFAULT_ON_CREATE') }}
        </label>
        <div class="flex justify-end gap-2">
          <NextButton
            type="button"
            ghost
            slate
            :label="t('CADENCE.DEFINITIONS.CANCEL')"
            @click="cancelAdd"
          />
          <NextButton
            type="button"
            :label="t('CADENCE.DEFINITIONS.SAVE')"
            @click="createDefinition"
          />
        </div>
      </div>

      <div v-else class="w-full flex justify-start py-2">
        <NextButton
          type="button"
          ghost
          icon="i-lucide-plus"
          :label="t('CADENCE.DEFINITIONS.ADD')"
          @click="openAddForm"
        />
      </div>
    </div>

    <woot-delete-modal
      v-model:show="showDeleteConfirmation"
      :on-close="closeDeleteConfirmation"
      :on-confirm="confirmDelete"
      :title="t('CADENCE.DEFINITIONS.DELETE.CONFIRM_TITLE')"
      :message="t('CADENCE.DEFINITIONS.DELETE.CONFIRM_MESSAGE')"
      :confirm-text="t('CADENCE.DEFINITIONS.DELETE.CONFIRM_YES')"
      :reject-text="t('CADENCE.DEFINITIONS.DELETE.CONFIRM_NO')"
    />
  </div>
</template>
