<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CallAnalysesAPI from 'dashboard/api/callAnalyses';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'shared/components/Spinner.vue';

const { t } = useI18n();

const dialogRef = ref(null);
const isLoading = ref(false);
const detail = ref(null);

const humanize = value => {
  if (!value) return '—';
  return String(value)
    .replaceAll('_', ' ')
    .replace(/^./, c => c.toUpperCase());
};

const confidenceColorClass = computed(() => {
  const map = {
    high: 'bg-n-teal-3 text-n-teal-11',
    medium: 'bg-n-amber-3 text-n-amber-11',
    low: 'bg-n-ruby-3 text-n-ruby-11',
  };
  return map[detail.value?.confidence] || 'bg-n-alpha-2 text-n-slate-12';
});

const readingColorClass = computed(() => {
  const map = {
    solido: 'bg-n-teal-3 text-n-teal-11',
    coaching: 'bg-n-amber-3 text-n-amber-11',
    critico: 'bg-n-ruby-3 text-n-ruby-11',
  };
  return (
    map[detail.value?.scorecard?.reading] || 'bg-n-alpha-2 text-n-slate-12'
  );
});

const stageEntries = computed(() => {
  const evidence = detail.value?.scorecard_stage_evidence || {};
  const scores = detail.value?.scorecard?.stage_scores || {};
  const stages = new Set([...Object.keys(evidence), ...Object.keys(scores)]);
  return [...stages].map(stage => ({
    stage,
    score: evidence[stage]?.score ?? scores[stage],
    evidenceText: evidence[stage]?.evidence,
  }));
});

const qualificationEntries = computed(() => {
  const map = detail.value?.qualification_map || {};
  return Object.entries(map).map(([key, value]) => ({
    key,
    captured: !!value?.captured,
    evidenceText: value?.evidence,
  }));
});

const formatDate = value => {
  if (!value) return '—';
  return new Date(value * 1000 || value).toLocaleString();
};

const formatDuration = seconds => {
  if (seconds === null || seconds === undefined) return '—';
  return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
};

const openConversation = () => {
  const conversationId = detail.value?.call?.conversation_id;
  if (!conversationId) return;
  window.open(
    `/app/accounts/${window.location.pathname.split('/')[2]}/conversations/${conversationId}`,
    '_blank'
  );
};

const open = async callAnalysisId => {
  dialogRef.value?.open();
  isLoading.value = true;
  detail.value = null;
  try {
    const response = await CallAnalysesAPI.getDetail(callAnalysisId);
    detail.value = response.data;
  } catch (error) {
    useAlert(t('CALL_ANALYSIS_DETAIL.ERRORS.FETCH'));
    dialogRef.value?.close();
  } finally {
    isLoading.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="t('CALL_ANALYSIS_DETAIL.TITLE')"
    width="2xl"
    overflow-y-auto
    :show-cancel-button="false"
    :show-confirm-button="false"
  >
    <div v-if="isLoading" class="flex justify-center py-8">
      <Spinner />
    </div>
    <div v-else-if="detail" class="flex flex-col gap-5 text-sm">
      <div class="flex flex-wrap gap-2 items-center">
        <span class="px-2 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-12">
          {{ humanize(detail.role) }}
        </span>
        <span class="px-2 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-12">
          {{ humanize(detail.conversation_type) }}
        </span>
        <span class="px-2 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-12">
          {{ humanize(detail.outcome_type) }}
        </span>
        <span class="px-2 py-0.5 rounded-full" :class="confidenceColorClass">
          {{ t('CALL_ANALYSIS_DETAIL.CONFIDENCE') }}:
          {{ humanize(detail.confidence) }}
        </span>
      </div>

      <div class="text-n-slate-11">
        {{ formatDate(detail.call?.started_at) }} ·
        {{ formatDuration(detail.call?.duration_seconds) }} ·
        {{ detail.agent_name || '—' }}
        <button
          v-if="detail.call?.conversation_id"
          type="button"
          class="text-n-blue-11 underline ml-1"
          @click="openConversation"
        >
          {{ t('CALL_ANALYSIS_DETAIL.OPEN_CONVERSATION') }}
        </button>
      </div>

      <div
        v-if="detail.scorecard?.total_score != null"
        class="p-3 rounded-lg bg-n-alpha-1"
      >
        <div class="flex items-center gap-2 mb-2">
          <span class="font-medium text-n-slate-12">
            {{ t('CALL_ANALYSIS_DETAIL.SCORECARD.TOTAL') }}:
            {{ detail.scorecard.total_score }}
          </span>
          <span
            class="px-2 py-0.5 rounded-full text-xs"
            :class="readingColorClass"
          >
            {{ humanize(detail.scorecard.reading) }}
          </span>
        </div>
        <ul class="flex flex-col gap-1 pl-4 list-disc">
          <li v-for="row in stageEntries" :key="row.stage">
            <span class="font-medium">{{ humanize(row.stage) }}:</span>
            {{ row.score ?? '—' }}
            <span v-if="row.evidenceText" class="text-n-slate-11">
              — {{ row.evidenceText }}
            </span>
          </li>
        </ul>
      </div>

      <div v-if="qualificationEntries.length">
        <h4 class="text-sm font-semibold text-n-slate-12 mb-2">
          {{ t('CALL_ANALYSIS_DETAIL.QUALIFICATION_MAP') }}
        </h4>
        <ul class="flex flex-col gap-1 pl-4 list-disc">
          <li v-for="item in qualificationEntries" :key="item.key">
            <span :class="item.captured ? 'text-n-teal-11' : 'text-n-slate-11'">
              {{ item.captured ? '✓' : '—' }} {{ humanize(item.key) }}
            </span>
            <span v-if="item.evidenceText" class="text-n-slate-11">
              — {{ item.evidenceText }}
            </span>
          </li>
        </ul>
      </div>

      <div v-if="detail.objections?.length">
        <h4 class="text-sm font-semibold text-n-slate-12 mb-2">
          {{ t('CALL_ANALYSIS_DETAIL.OBJECTIONS') }}
        </h4>
        <ul class="flex flex-col gap-2">
          <li
            v-for="(objection, index) in detail.objections"
            :key="index"
            class="p-2 rounded-lg bg-n-alpha-1"
          >
            <div class="font-medium">
              {{ humanize(objection.category) }}
              <span v-if="objection.subtype" class="text-n-slate-11">
                ({{ objection.subtype }})
              </span>
            </div>
            <div v-if="objection.quote" class="italic text-n-slate-11">
              {{ t('CALL_ANALYSIS_DETAIL.QUOTE', { text: objection.quote }) }}
            </div>
            <div v-if="objection.response" class="text-n-slate-11">
              {{ t('CALL_ANALYSIS_DETAIL.OBJECTION_RESPONSE') }}:
              {{ objection.response }}
            </div>
          </li>
        </ul>
      </div>

      <div v-if="detail.risks?.length">
        <h4 class="text-sm font-semibold text-n-slate-12 mb-2">
          {{ t('CALL_ANALYSIS_DETAIL.RISKS') }}
        </h4>
        <ul class="flex flex-col gap-1 pl-4 list-disc">
          <li v-for="(risk, index) in detail.risks" :key="index">
            <span class="font-medium">{{ humanize(risk.type) }}:</span>
            <span class="text-n-slate-11">{{ risk.evidence }}</span>
          </li>
        </ul>
      </div>

      <details v-if="detail.call?.transcript_segments?.length">
        <summary class="cursor-pointer text-n-slate-12 font-medium">
          {{ t('CALL_ANALYSIS_DETAIL.TRANSCRIPT') }}
        </summary>
        <div class="mt-2 flex flex-col gap-1 text-n-slate-11">
          <p
            v-for="(segment, index) in detail.call.transcript_segments"
            :key="index"
          >
            <span class="font-medium">{{ segment.speaker }}:</span>
            {{ segment.text }}
          </p>
        </div>
      </details>
    </div>
  </Dialog>
</template>
