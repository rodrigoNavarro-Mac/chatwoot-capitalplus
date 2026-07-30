<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import SalesFunnelGoalsAPI from 'dashboard/api/salesFunnelGoals';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  developmentKeys: {
    type: Array,
    default: () => [],
  },
});

const emit = defineEmits(['saved']);

const { t } = useI18n();

const STAGES = ['leads', 'customer_replied', 'has_deal', 'closed_won'];

const goals = ref([]);
const isLoading = ref(false);

const toMonthInputValue = date => date.toISOString().slice(0, 7);

const newGoal = ref({
  developmentKey: props.developmentKeys[0] || '',
  stage: STAGES[0],
  periodMonth: toMonthInputValue(new Date()),
  targetPercent: 30,
});

const fetchGoals = async () => {
  isLoading.value = true;
  try {
    const response = await SalesFunnelGoalsAPI.get();
    goals.value = response.data;
  } finally {
    isLoading.value = false;
  }
};

const addGoal = async () => {
  if (!newGoal.value.developmentKey) return;

  try {
    const response = await SalesFunnelGoalsAPI.create({
      development_key: newGoal.value.developmentKey,
      stage: newGoal.value.stage,
      period_month: `${newGoal.value.periodMonth}-01`,
      target_percent: newGoal.value.targetPercent,
    });
    goals.value = response.data;
    emit('saved');
  } catch (error) {
    useAlert(t('SALES_FUNNEL_REPORTS.GOALS.ERRORS.SAVE'));
  }
};

const deleteGoal = async id => {
  try {
    await SalesFunnelGoalsAPI.delete(id);
    goals.value = goals.value.filter(goal => goal.id !== id);
    emit('saved');
  } catch (error) {
    useAlert(t('SALES_FUNNEL_REPORTS.GOALS.ERRORS.DELETE'));
  }
};

onMounted(fetchGoals);
</script>

<template>
  <div class="flex flex-col gap-3">
    <h3 class="text-base font-medium text-n-slate-12 m-0">
      {{ t('SALES_FUNNEL_REPORTS.GOALS.TITLE') }}
    </h3>

    <div class="flex flex-wrap items-end gap-2">
      <div class="flex flex-col gap-1">
        <label class="text-xs text-n-slate-11">
          {{ t('SALES_FUNNEL_REPORTS.GOALS.DEVELOPMENT') }}
        </label>
        <input
          v-model="newGoal.developmentKey"
          list="sales-funnel-development-keys"
          type="text"
          class="!mb-0 !h-8 text-sm"
        />
        <datalist id="sales-funnel-development-keys">
          <option v-for="key in developmentKeys" :key="key" :value="key" />
        </datalist>
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-xs text-n-slate-11">
          {{ t('SALES_FUNNEL_REPORTS.GOALS.STAGE') }}
        </label>
        <select v-model="newGoal.stage" class="!mb-0 !h-8 text-sm">
          <option v-for="stage in STAGES" :key="stage" :value="stage">
            {{ t(`SALES_FUNNEL_REPORTS.STAGES.${stage}`) }}
          </option>
        </select>
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-xs text-n-slate-11">
          {{ t('SALES_FUNNEL_REPORTS.GOALS.MONTH') }}
        </label>
        <input
          v-model="newGoal.periodMonth"
          type="month"
          class="!mb-0 !h-8 text-sm"
        />
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-xs text-n-slate-11">
          {{ t('SALES_FUNNEL_REPORTS.GOALS.TARGET_PERCENT') }}
        </label>
        <input
          v-model.number="newGoal.targetPercent"
          type="number"
          min="0"
          max="100"
          class="!mb-0 !h-8 w-20 text-sm"
        />
      </div>
      <Button
        size="sm"
        :label="t('SALES_FUNNEL_REPORTS.GOALS.ADD')"
        @click="addGoal"
      />
    </div>

    <div
      v-if="!isLoading && goals.length"
      class="overflow-x-auto border border-n-weak rounded-lg"
    >
      <table class="min-w-full text-sm">
        <thead class="bg-n-slate-2">
          <tr class="text-left text-n-slate-11">
            <th class="px-3 py-2">
              {{ t('SALES_FUNNEL_REPORTS.GOALS.DEVELOPMENT') }}
            </th>
            <th class="px-3 py-2">
              {{ t('SALES_FUNNEL_REPORTS.GOALS.STAGE') }}
            </th>
            <th class="px-3 py-2">
              {{ t('SALES_FUNNEL_REPORTS.GOALS.MONTH') }}
            </th>
            <th class="px-3 py-2">
              {{ t('SALES_FUNNEL_REPORTS.GOALS.TARGET_PERCENT') }}
            </th>
            <th class="px-3 py-2" />
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak">
          <tr v-for="goal in goals" :key="goal.id" class="text-n-slate-12">
            <td class="px-3 py-2 font-medium">{{ goal.development_key }}</td>
            <td class="px-3 py-2">
              {{ t(`SALES_FUNNEL_REPORTS.STAGES.${goal.stage}`) }}
            </td>
            <td class="px-3 py-2">{{ goal.period_month }}</td>
            <td class="px-3 py-2">{{ goal.target_percent }}%</td>
            <td class="px-3 py-2">
              <Button
                variant="ghost"
                color="ruby"
                size="xs"
                icon="i-lucide-trash-2"
                :label="t('SALES_FUNNEL_REPORTS.GOALS.DELETE')"
                @click="deleteGoal(goal.id)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
