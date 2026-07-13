<script setup>
import { ref, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CadencesAPI from 'dashboard/api/cadences';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SpinnerLoader from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  inbox: { type: Object, required: true },
});

const { t } = useI18n();

const isLoading = ref(false);
const isSaving = ref(false);
const entries = ref([]);

const fetchMappings = async () => {
  if (!props.inbox?.id) return;
  isLoading.value = true;
  try {
    const { data } = await CadencesAPI.getTemplateMappings(props.inbox.id);
    entries.value = data;
  } catch (error) {
    useAlert(t('CADENCE.TEMPLATES_SETTINGS.ERRORS.FETCH'));
  } finally {
    isLoading.value = false;
  }
};

const save = async () => {
  isSaving.value = true;
  try {
    const { data } = await CadencesAPI.updateTemplateMappings(
      props.inbox.id,
      entries.value.map(entry => ({
        template_key: entry.template_key,
        name: entry.name,
        language: entry.language,
        namespace: entry.namespace,
      }))
    );
    entries.value = data;
    useAlert(t('CADENCE.TEMPLATES_SETTINGS.SUCCESS'));
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('CADENCE.TEMPLATES_SETTINGS.ERRORS.SAVE')
    );
  } finally {
    isSaving.value = false;
  }
};

const resetToDefault = async templateKey => {
  try {
    const { data } = await CadencesAPI.resetTemplateMapping(
      props.inbox.id,
      templateKey
    );
    entries.value = data;
    useAlert(t('CADENCE.TEMPLATES_SETTINGS.RESET_SUCCESS'));
  } catch (error) {
    useAlert(t('CADENCE.TEMPLATES_SETTINGS.ERRORS.RESET'));
  }
};

onMounted(fetchMappings);
watch(() => props.inbox?.id, fetchMappings);
</script>

<template>
  <div class="mx-6 max-w-4xl">
    <div class="flex flex-col gap-1 mb-4">
      <h3 class="text-heading-3 text-n-slate-12">
        {{ t('CADENCE.TEMPLATES_SETTINGS.TITLE') }}
      </h3>
      <p class="text-n-slate-11 text-body-2">
        {{ t('CADENCE.TEMPLATES_SETTINGS.DESCRIPTION') }}
      </p>
    </div>

    <div v-if="isLoading" class="flex justify-center py-8">
      <SpinnerLoader :size="28" />
    </div>

    <div v-else class="flex flex-col gap-4">
      <div
        v-for="entry in entries"
        :key="entry.template_key"
        class="flex flex-col gap-2 p-4 rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
      >
        <div class="flex items-center justify-between">
          <span class="text-heading-3 text-n-slate-12">
            {{ t(`CADENCE.STEP_KEYS.${entry.template_key}`) }}
          </span>
          <NextButton
            v-if="entry.is_custom"
            type="button"
            ghost
            slate
            xs
            :label="t('CADENCE.TEMPLATES_SETTINGS.RESET')"
            @click="resetToDefault(entry.template_key)"
          />
        </div>
        <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
          <Input
            v-model="entry.name"
            :label="t('CADENCE.TEMPLATES_SETTINGS.TEMPLATE_NAME')"
          />
          <Input
            v-model="entry.language"
            :label="t('CADENCE.TEMPLATES_SETTINGS.TEMPLATE_LANGUAGE')"
          />
        </div>
      </div>

      <div class="w-full flex justify-end py-4">
        <NextButton
          type="submit"
          :label="t('CADENCE.TEMPLATES_SETTINGS.SAVE')"
          :is-loading="isSaving"
          @click="save"
        />
      </div>
    </div>
  </div>
</template>
