<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ZohoCrmAPI from '../../../api/integrations/zoho_crm';

const props = defineProps({
  contactId: {
    type: [Number, String],
    required: true,
  },
  conversationId: {
    type: [Number, String],
    default: null,
  },
});

const { t } = useI18n();

const record = ref({});
const notes = ref([]);
const tasks = ref([]);
const meetings = ref([]);
const isLoading = ref(false);
const errorCode = ref(null);
const expandedNotes = ref({});

const zohoModuleRef = ref('Leads');
const zohoRecordUrl = ref(null);
const recordExists = ref(true);
const stageOptionsServer = ref([]);
const conversationData = ref([]);

const isCreatingLead = ref(false);
const createLeadError = ref(null);

const isUpdatingStage = ref(false);
const stageSaveSuccess = ref(false);
const stageUpdateError = ref(null);
const selectedStage = ref('');

const isPushingToCrm = ref(false);
const pushCrmSuccess = ref(false);
const pushCrmError = ref(null);

const showNoteForm = ref(false);
const noteContent = ref('');
const isSavingNote = ref(false);
const noteSaveError = ref(null);

const showDealForm = ref(false);
const dealName = ref('');
const dealStage = ref('');
const isCreatingDeal = ref(false);
const createDealError = ref(null);
const dealCreated = ref(null);

const isLead = computed(() => zohoModuleRef.value === 'Leads');
const isDeal = computed(() => zohoModuleRef.value === 'Deals');
const isContact = computed(() => zohoModuleRef.value === 'Contacts');
const hasStage = computed(() => isLead.value || isDeal.value);

const moduleLabel = computed(() => {
  if (isLead.value) return 'Lead';
  if (isDeal.value) return 'Deal';
  if (isContact.value) return t('INTEGRATION_SETTINGS.ZOHO_CRM.MODULE_CONTACT');
  return zohoModuleRef.value;
});

const moduleBadgeClass = computed(() => {
  if (isLead.value) return 'bg-n-amber-3 text-n-amber-11';
  if (isDeal.value) return 'bg-n-teal-3 text-n-teal-11';
  return 'bg-n-blue-3 text-n-blue-11';
});

const LEAD_STATUSES_FALLBACK = [
  'Nuevo contacto',
  'Intento de contacto',
  'Contacto no exitoso',
  'Contactar en el futuro',
  'Contactado',
  'Cliente perdido/Descartado',
].map(s => ({ label: s, value: s }));

const DEAL_STAGES_FALLBACK = [
  'Qualification',
  'Needs Analysis',
  'Value Proposition',
  'Id. Decision Makers',
  'Perception Analysis',
  'Proposal/Price Quote',
  'Negotiation/Review',
  'Closed Won',
  'Closed Lost',
  'Closed Lost to Competition',
].map(s => ({ label: s, value: s }));

const stageOptions = computed(() => {
  if (stageOptionsServer.value.length > 0) return stageOptionsServer.value;
  return isDeal.value ? DEAL_STAGES_FALLBACK : LEAD_STATUSES_FALLBACK;
});

const stageLabel = computed(() =>
  isDeal.value
    ? t('INTEGRATION_SETTINGS.ZOHO_CRM.STAGE_LABEL')
    : t('INTEGRATION_SETTINGS.ZOHO_CRM.STATUS_LABEL')
);

const currentStage = computed(
  () => record.value?.Lead_Status || record.value?.Stage || ''
);

const fetchData = async () => {
  if (!props.contactId) return;
  isLoading.value = true;
  errorCode.value = null;
  record.value = {};
  notes.value = [];
  tasks.value = [];
  meetings.value = [];
  try {
    const response = await ZohoCrmAPI.getContactData(
      props.contactId,
      props.conversationId
    );
    const data = response.data;
    zohoModuleRef.value = data.zoho_module || 'Leads';
    zohoRecordUrl.value = data.zoho_record_url || null;
    recordExists.value = data.record_exists !== false;
    stageOptionsServer.value = data.stage_options || [];
    record.value = data.record || {};
    notes.value = data.notes || [];
    tasks.value = data.tasks || [];
    meetings.value = data.meetings || [];
    selectedStage.value = currentStage.value;
    conversationData.value = data.conversation_data || [];
  } catch (e) {
    errorCode.value = e.response?.data?.error || 'error';
  } finally {
    isLoading.value = false;
  }
};

watch(() => props.contactId, fetchData, { immediate: true });

const createLead = async () => {
  isCreatingLead.value = true;
  createLeadError.value = null;
  try {
    await ZohoCrmAPI.createLead(props.contactId, props.conversationId);
    await fetchData();
  } catch (e) {
    createLeadError.value =
      e.response?.data?.error ||
      t('INTEGRATION_SETTINGS.ZOHO_CRM.CREATE_LEAD_ERROR');
  } finally {
    isCreatingLead.value = false;
  }
};

const pushToCrm = async () => {
  isPushingToCrm.value = true;
  pushCrmSuccess.value = false;
  pushCrmError.value = null;
  try {
    await ZohoCrmAPI.pushToCrm(props.contactId, props.conversationId);
    pushCrmSuccess.value = true;
    setTimeout(() => {
      pushCrmSuccess.value = false;
    }, 3000);
  } catch (e) {
    pushCrmError.value =
      e.response?.data?.error || t('INTEGRATION_SETTINGS.ZOHO_CRM.SYNC_ERROR');
    setTimeout(() => {
      pushCrmError.value = null;
    }, 4000);
  } finally {
    isPushingToCrm.value = false;
  }
};

const updateStage = async () => {
  if (!selectedStage.value || selectedStage.value === currentStage.value)
    return;
  isUpdatingStage.value = true;
  stageSaveSuccess.value = false;
  stageUpdateError.value = null;
  try {
    await ZohoCrmAPI.updateStage(props.contactId, selectedStage.value);
    if (zohoModuleRef.value === 'Deals') {
      record.value = { ...record.value, Stage: selectedStage.value };
    } else {
      record.value = { ...record.value, Lead_Status: selectedStage.value };
    }
    stageSaveSuccess.value = true;
    setTimeout(() => {
      stageSaveSuccess.value = false;
    }, 2000);
  } catch (e) {
    selectedStage.value = currentStage.value;
    stageUpdateError.value =
      e.response?.data?.error ||
      t('INTEGRATION_SETTINGS.ZOHO_CRM.STAGE_UPDATE_ERROR');
    setTimeout(() => {
      stageUpdateError.value = null;
    }, 4000);
  } finally {
    isUpdatingStage.value = false;
  }
};

const openDealForm = () => {
  dealName.value = '';
  dealStage.value = DEAL_STAGES_FALLBACK[0].value;
  createDealError.value = null;
  dealCreated.value = null;
  showDealForm.value = true;
};

const cancelDeal = () => {
  showDealForm.value = false;
  createDealError.value = null;
};

const saveDeal = async () => {
  if (!dealName.value.trim()) return;
  isCreatingDeal.value = true;
  createDealError.value = null;
  try {
    const response = await ZohoCrmAPI.createDeal(
      props.contactId,
      dealName.value.trim(),
      dealStage.value
    );
    dealCreated.value = response.data.deal_name;
    showDealForm.value = false;
  } catch (e) {
    createDealError.value =
      e.response?.data?.error ||
      t('INTEGRATION_SETTINGS.ZOHO_CRM.CREATE_DEAL_ERROR');
  } finally {
    isCreatingDeal.value = false;
  }
};

const saveNote = async () => {
  if (!noteContent.value.trim()) return;
  isSavingNote.value = true;
  noteSaveError.value = null;
  try {
    await ZohoCrmAPI.createCrmNote(props.contactId, noteContent.value.trim());
    noteContent.value = '';
    showNoteForm.value = false;
    await fetchData();
  } catch (e) {
    noteSaveError.value =
      e.response?.data?.error ||
      t('INTEGRATION_SETTINGS.ZOHO_CRM.SAVE_NOTE_ERROR');
  } finally {
    isSavingNote.value = false;
  }
};

const cancelNote = () => {
  noteContent.value = '';
  noteSaveError.value = null;
  showNoteForm.value = false;
};

const toggleNote = id => {
  expandedNotes.value[id] = !expandedNotes.value[id];
};

const truncate = (text, len = 150) => {
  if (!text) return '';
  return text.length > len ? text.slice(0, len) + '…' : text;
};

const formatDate = dateStr => {
  if (!dateStr) return '';
  return new Date(dateStr).toLocaleDateString(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  });
};

const taskStatusClass = status =>
  status === 'Completed'
    ? 'bg-n-teal-3 text-n-teal-11'
    : 'bg-n-amber-3 text-n-amber-11';

const priorityLabel = priority => {
  const map = { High: 'Alta', Medium: 'Media', Low: 'Baja' };
  return map[priority] || priority || '—';
};
</script>

<template>
  <div class="px-4 py-2 text-n-slate-12 text-sm">
    <!-- Cargando -->
    <div v-if="isLoading" class="flex justify-center items-center p-4">
      <Spinner size="24" class="text-n-brand" />
    </div>

    <!-- Error: integración no configurada -->
    <div
      v-else-if="errorCode === 'not_connected'"
      class="text-center text-n-slate-9 py-3"
    >
      {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.NOT_CONNECTED') }}
    </div>

    <!-- Error: contacto sin zoho_id → botón Crear Lead -->
    <div v-else-if="errorCode === 'not_linked'" class="py-3">
      <p class="text-center text-n-slate-9 mb-3 text-xs">
        {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.NOT_LINKED') }}
      </p>
      <p v-if="createLeadError" class="text-center text-n-ruby-11 text-xs mb-2">
        {{ createLeadError }}
      </p>
      <button
        class="w-full flex items-center justify-center gap-1.5 rounded-lg bg-n-brand px-3 py-1.5 text-white text-xs font-medium hover:bg-n-brand/90 disabled:opacity-60 transition-colors"
        :disabled="isCreatingLead"
        @click="createLead"
      >
        <Spinner v-if="isCreatingLead" size="14" />
        <span v-else>{{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.ADD_ICON') }}</span>
        {{
          isCreatingLead
            ? $t('INTEGRATION_SETTINGS.ZOHO_CRM.CREATING_LEAD')
            : $t('INTEGRATION_SETTINGS.ZOHO_CRM.CREATE_LEAD')
        }}
      </button>
    </div>

    <!-- Error genérico -->
    <div v-else-if="errorCode" class="text-center text-n-ruby-11 py-3">
      {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.LOAD_ERROR') }}
    </div>

    <!-- Vista principal (vinculado) -->
    <div v-else class="flex flex-col gap-4">
      <!-- Registro eliminado en Zoho pero tiene zoho_id → Re-crear -->
      <div
        v-if="!recordExists"
        class="rounded-lg border border-n-amber-5 bg-n-amber-2 p-3"
      >
        <p class="text-n-amber-11 text-xs mb-2">
          {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.RECORD_NOT_EXISTS') }}
        </p>
        <p v-if="createLeadError" class="text-n-ruby-11 text-xs mb-2">
          {{ createLeadError }}
        </p>
        <button
          class="w-full flex items-center justify-center gap-1.5 rounded bg-n-brand px-3 py-1.5 text-white text-xs font-medium hover:bg-n-brand/90 disabled:opacity-60 transition-colors"
          :disabled="isCreatingLead"
          @click="createLead"
        >
          <Spinner v-if="isCreatingLead" size="14" />
          <span v-else>{{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.ADD_ICON') }}</span>
          {{
            isCreatingLead
              ? $t('INTEGRATION_SETTINGS.ZOHO_CRM.CREATING_LEAD')
              : $t('INTEGRATION_SETTINGS.ZOHO_CRM.CREATE_NEW_LEAD')
          }}
        </button>
      </div>

      <!-- Cabecera: badge de módulo + campos resumen + sync -->
      <div v-if="recordExists">
        <!-- Fila superior: badge + botón sync -->
        <div class="flex items-center justify-between mb-2">
          <a
            v-if="zohoRecordUrl"
            :href="zohoRecordUrl"
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold hover:opacity-75 transition-opacity"
            :class="moduleBadgeClass"
            :title="
              $t('INTEGRATION_SETTINGS.ZOHO_CRM.OPEN_IN_ZOHO', {
                module: moduleLabel,
              })
            "
          >
            {{ moduleLabel }}
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-3 w-3"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2.5"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <path
                d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"
              />
              <polyline points="15 3 21 3 21 9" />
              <line x1="10" y1="14" x2="21" y2="3" />
            </svg>
          </a>
          <span
            v-else
            class="inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold"
            :class="moduleBadgeClass"
          >
            {{ moduleLabel }}
          </span>
          <button
            class="rounded p-1 text-n-slate-9 hover:text-n-brand hover:bg-n-slate-3 transition-colors"
            :title="$t('INTEGRATION_SETTINGS.ZOHO_CRM.REFRESH')"
            @click="fetchData"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-3.5 w-3.5"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <path d="M21 2v6h-6" />
              <path d="M3 12a9 9 0 0 1 15-6.7L21 8" />
              <path d="M3 22v-6h6" />
              <path d="M21 12a9 9 0 0 1-15 6.7L3 16" />
            </svg>
          </button>
        </div>

        <!-- Campos resumen por tipo de módulo -->
        <div
          class="rounded-lg bg-n-slate-2 px-3 py-2 text-xs flex flex-col gap-1 mb-3"
        >
          <!-- Lead -->
          <template v-if="isLead">
            <div v-if="record.Company" class="flex gap-1.5 text-n-slate-9">
              <span class="shrink-0">
                {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.FIELD_COMPANY') }}
              </span>
              <span class="text-n-slate-12 font-medium truncate">
                {{ record.Company }}
              </span>
            </div>
            <div v-if="record.Owner?.name" class="flex gap-1.5 text-n-slate-9">
              <span class="shrink-0">
                {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.FIELD_ASSIGNED') }}
              </span>
              <span class="text-n-slate-12 truncate">
                {{ record.Owner.name }}
              </span>
            </div>
          </template>

          <!-- Deal -->
          <template v-else-if="isDeal">
            <div v-if="record.Account_Name" class="flex gap-1.5 text-n-slate-9">
              <span class="shrink-0">
                {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.FIELD_ACCOUNT') }}
              </span>
              <span class="text-n-slate-12 font-medium truncate">
                {{ record.Account_Name }}
              </span>
            </div>
            <div
              v-if="record.Amount != null"
              class="flex gap-1.5 text-n-slate-9"
            >
              <span class="shrink-0">
                {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.FIELD_AMOUNT') }}
              </span>
              <span class="text-n-slate-12 font-medium">
                {{
                  record.Amount?.toLocaleString('es-MX', {
                    style: 'currency',
                    currency: 'MXN',
                  })
                }}
              </span>
            </div>
            <div v-if="record.Closing_Date" class="flex gap-1.5 text-n-slate-9">
              <span class="shrink-0">
                {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.FIELD_CLOSING') }}
              </span>
              <span class="text-n-slate-12">
                {{ formatDate(record.Closing_Date) }}
              </span>
            </div>
            <div v-if="record.Owner?.name" class="flex gap-1.5 text-n-slate-9">
              <span class="shrink-0">
                {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.FIELD_ASSIGNED') }}
              </span>
              <span class="text-n-slate-12 truncate">
                {{ record.Owner.name }}
              </span>
            </div>
          </template>

          <!-- Contact -->
          <template v-else-if="isContact">
            <div v-if="record.Title" class="flex gap-1.5 text-n-slate-9">
              <span class="shrink-0">
                {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.FIELD_TITLE') }}
              </span>
              <span class="text-n-slate-12 font-medium truncate">
                {{ record.Title }}
              </span>
            </div>
            <div v-if="record.Account_Name" class="flex gap-1.5 text-n-slate-9">
              <span class="shrink-0">
                {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.FIELD_COMPANY') }}
              </span>
              <span class="text-n-slate-12 truncate">
                {{ record.Account_Name }}
              </span>
            </div>
            <div v-if="record.Owner?.name" class="flex gap-1.5 text-n-slate-9">
              <span class="shrink-0">
                {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.FIELD_ASSIGNED') }}
              </span>
              <span class="text-n-slate-12 truncate">
                {{ record.Owner.name }}
              </span>
            </div>
          </template>
        </div>

        <!-- Crear Deal (solo cuando es Contacto) -->
        <div v-if="isContact" class="mb-3">
          <!-- Éxito -->
          <div
            v-if="dealCreated"
            class="rounded-lg border border-n-teal-5 bg-n-teal-2 px-3 py-2 text-xs text-n-teal-11 flex items-center justify-between"
          >
            <span>
              {{
                $t('INTEGRATION_SETTINGS.ZOHO_CRM.DEAL_CREATED', {
                  name: dealCreated,
                })
              }}
            </span>
            <button
              class="ml-2 text-n-teal-9 hover:text-n-teal-11"
              @click="dealCreated = null"
            >
              {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.DISMISS') }}
            </button>
          </div>

          <!-- Formulario -->
          <div
            v-else-if="showDealForm"
            class="rounded-lg border border-n-slate-4 p-3 flex flex-col gap-2"
          >
            <p class="text-xs font-semibold text-n-slate-11">
              {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.NEW_DEAL') }}
            </p>
            <div>
              <label class="text-xs text-n-slate-9 mb-0.5 block">
                {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.DEAL_NAME_LABEL') }}
              </label>
              <input
                v-model="dealName"
                type="text"
                :placeholder="
                  $t('INTEGRATION_SETTINGS.ZOHO_CRM.DEAL_NAME_PLACEHOLDER')
                "
                class="w-full rounded border border-n-slate-5 bg-n-slate-1 px-2 py-1 text-xs text-n-slate-12 focus:outline-none focus:border-n-brand"
              />
            </div>
            <div>
              <label class="text-xs text-n-slate-9 mb-0.5 block">
                {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.INITIAL_STAGE') }}
              </label>
              <select
                v-model="dealStage"
                class="w-full rounded border border-n-slate-5 bg-n-slate-1 px-2 py-1 text-xs text-n-slate-12 focus:outline-none focus:border-n-brand"
              >
                <option
                  v-for="opt in DEAL_STAGES_FALLBACK"
                  :key="opt.value"
                  :value="opt.value"
                >
                  {{ opt.label }}
                </option>
              </select>
            </div>
            <p v-if="createDealError" class="text-n-ruby-11 text-xs">
              {{ createDealError }}
            </p>
            <div class="flex gap-2">
              <button
                class="flex-1 flex items-center justify-center gap-1 rounded bg-n-teal-9 px-2 py-1 text-white text-xs font-medium hover:bg-n-teal-10 disabled:opacity-60 transition-colors"
                :disabled="isCreatingDeal || !dealName.trim()"
                @click="saveDeal"
              >
                <Spinner v-if="isCreatingDeal" size="12" />
                {{
                  isCreatingDeal
                    ? $t('INTEGRATION_SETTINGS.ZOHO_CRM.CREATING')
                    : $t('INTEGRATION_SETTINGS.ZOHO_CRM.CREATE_DEAL')
                }}
              </button>
              <button
                class="rounded px-2 py-1 text-n-slate-9 text-xs hover:text-n-slate-12 transition-colors"
                @click="cancelDeal"
              >
                {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.CANCEL') }}
              </button>
            </div>
          </div>

          <!-- Botón para abrir el formulario -->
          <button
            v-else
            class="w-full flex items-center justify-center gap-1.5 rounded-lg border border-n-teal-5 text-n-teal-11 px-3 py-1.5 text-xs font-medium hover:bg-n-teal-2 transition-colors"
            @click="openDealForm"
          >
            {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.CREATE_DEAL_IN_ZOHO') }}
          </button>
        </div>

        <!-- Dropdown de estado (solo Lead y Deal) -->
        <div v-if="hasStage">
          <label class="block text-n-slate-9 text-xs mb-0.5">
            {{ stageLabel }}
          </label>
          <div class="flex items-center gap-1.5">
            <select
              v-model="selectedStage"
              class="flex-1 min-w-0 rounded border border-n-slate-5 bg-n-slate-1 px-2 py-1 text-xs text-n-slate-12 focus:outline-none focus:border-n-brand"
              :disabled="isUpdatingStage"
              @change="updateStage"
            >
              <option value="" disabled>
                {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.NO_STATUS') }}
              </option>
              <option
                v-for="opt in stageOptions"
                :key="opt.value"
                :value="opt.value"
              >
                {{ opt.label }}
              </option>
            </select>
            <Spinner
              v-if="isUpdatingStage"
              size="14"
              class="text-n-brand shrink-0"
            />
            <span
              v-else-if="stageSaveSuccess"
              class="shrink-0 text-n-teal-11 text-xs"
            >
              {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.CHECK_ICON') }}
            </span>
          </div>
          <p v-if="stageUpdateError" class="text-n-ruby-11 text-xs mt-1">
            {{ stageUpdateError }}
          </p>
        </div>
      </div>

      <!-- Datos capturados por el bot -->
      <div
        v-if="conversationData.length"
        class="rounded-lg border border-n-slate-4 bg-n-slate-2 p-2"
      >
        <div class="flex items-center justify-between mb-1.5">
          <p class="text-xs font-semibold text-n-slate-11">
            {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.CONVERSATION_DATA_TITLE') }}
          </p>
          <div class="flex items-center gap-1">
            <span v-if="pushCrmSuccess" class="text-n-teal-11 text-xs">
              {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.SENT') }}
            </span>
            <span v-else-if="pushCrmError" class="text-n-ruby-11 text-xs">
              {{ pushCrmError }}
            </span>
            <button
              class="flex items-center gap-1 rounded px-1.5 py-0.5 text-xs font-medium text-n-brand border border-n-brand hover:bg-n-brand/5 disabled:opacity-50 transition-colors"
              :disabled="isPushingToCrm"
              :title="
                $t('INTEGRATION_SETTINGS.ZOHO_CRM.SEND_TO_ZOHO_TITLE', {
                  module: moduleLabel,
                })
              "
              @click="pushToCrm"
            >
              <Spinner v-if="isPushingToCrm" size="10" />
              <span v-else>
                {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.SYNC_ICON') }}
              </span>
              {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.SEND_TO_ZOHO') }}
            </button>
          </div>
        </div>
        <div
          v-for="item in conversationData"
          :key="item.label"
          class="flex gap-1.5 text-xs py-0.5"
        >
          <span class="text-n-slate-9 shrink-0">{{ item.label + ':' }}</span>
          <span class="text-n-slate-12 font-medium">{{ item.value }}</span>
        </div>
      </div>

      <!-- Notas -->
      <div>
        <p class="font-semibold text-n-slate-11 mb-1">
          {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.NOTES_TITLE') }}
          <span class="text-n-slate-9 font-normal">
            {{ `(${notes.length})` }}
          </span>
        </p>
        <p v-if="!notes.length" class="text-n-slate-9 text-xs">
          {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.NO_NOTES') }}
        </p>
        <div
          v-for="note in notes"
          :key="note.id"
          class="border border-n-slate-4 rounded-lg p-2 mb-2 text-xs"
        >
          <p class="font-medium text-n-slate-12 truncate">
            {{ note.Note_Title }}
          </p>
          <p class="text-n-slate-9 mt-0.5">
            {{ formatDate(note.Created_Time) }}
          </p>
          <p class="mt-1 text-n-slate-11 whitespace-pre-wrap">
            {{
              expandedNotes[note.id]
                ? note.Note_Content
                : truncate(note.Note_Content)
            }}
          </p>
          <button
            v-if="note.Note_Content && note.Note_Content.length > 150"
            class="text-n-brand mt-1 cursor-pointer hover:underline"
            @click="toggleNote(note.id)"
          >
            {{
              expandedNotes[note.id]
                ? $t('INTEGRATION_SETTINGS.ZOHO_CRM.SEE_LESS')
                : $t('INTEGRATION_SETTINGS.ZOHO_CRM.SEE_MORE')
            }}
          </button>
        </div>
      </div>

      <!-- Tareas -->
      <div>
        <p class="font-semibold text-n-slate-11 mb-1">
          {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.TASKS_TITLE') }}
          <span class="text-n-slate-9 font-normal">
            {{ `(${tasks.length})` }}
          </span>
        </p>
        <p v-if="!tasks.length" class="text-n-slate-9 text-xs">
          {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.NO_TASKS') }}
        </p>
        <div
          v-for="task in tasks"
          :key="task.id"
          class="border border-n-slate-4 rounded-lg p-2 mb-2 text-xs"
        >
          <div class="flex items-start justify-between gap-2">
            <p class="font-medium text-n-slate-12">{{ task.Subject }}</p>
            <span
              v-if="task.Status"
              class="shrink-0 rounded px-1.5 py-0.5 text-xs font-medium"
              :class="taskStatusClass(task.Status)"
            >
              {{
                task.Status === 'Completed'
                  ? $t('INTEGRATION_SETTINGS.ZOHO_CRM.TASK_COMPLETED')
                  : $t('INTEGRATION_SETTINGS.ZOHO_CRM.TASK_PENDING')
              }}
            </span>
          </div>
          <div class="mt-1 flex flex-wrap gap-3 text-n-slate-9">
            <span v-if="task.Due_Date">
              {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.TASK_DUE') }}
              {{ formatDate(task.Due_Date) }}
            </span>
            <span v-if="task.Priority">
              {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.TASK_PRIORITY') }}
              {{ priorityLabel(task.Priority) }}
            </span>
          </div>
        </div>
      </div>

      <!-- Reuniones -->
      <div>
        <p class="font-semibold text-n-slate-11 mb-1">
          {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.MEETINGS_TITLE') }}
          <span class="text-n-slate-9 font-normal">
            {{ `(${meetings.length})` }}
          </span>
        </p>
        <p v-if="!meetings.length" class="text-n-slate-9 text-xs">
          {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.NO_MEETINGS') }}
        </p>
        <div
          v-for="meeting in meetings"
          :key="meeting.id"
          class="border border-n-slate-4 rounded-lg p-2 mb-2 text-xs"
        >
          <p class="font-medium text-n-slate-12">{{ meeting.Event_Title }}</p>
          <p v-if="meeting.Start_DateTime" class="text-n-slate-9 mt-0.5">
            {{ formatDate(meeting.Start_DateTime) }}
            <span v-if="meeting.End_DateTime">
              {{
                $t('INTEGRATION_SETTINGS.ZOHO_CRM.MEETING_SEPARATOR') +
                formatDate(meeting.End_DateTime)
              }}
            </span>
          </p>
          <p v-if="meeting.Venue" class="text-n-slate-9 mt-0.5">
            {{
              $t('INTEGRATION_SETTINGS.ZOHO_CRM.LOCATION_ICON') + meeting.Venue
            }}
          </p>
        </div>
      </div>

      <!-- Agregar nota al CRM -->
      <div class="border-t border-n-slate-4 pt-3">
        <button
          v-if="!showNoteForm"
          class="w-full text-left text-xs text-n-brand hover:underline"
          @click="showNoteForm = true"
        >
          {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.ADD_NOTE') }}
        </button>

        <div v-else>
          <p class="text-xs font-medium text-n-slate-11 mb-1.5">
            {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.NEW_NOTE') }}
          </p>
          <textarea
            v-model="noteContent"
            rows="3"
            :placeholder="$t('INTEGRATION_SETTINGS.ZOHO_CRM.NOTE_PLACEHOLDER')"
            class="w-full rounded border border-n-slate-5 bg-n-slate-1 px-2 py-1.5 text-xs text-n-slate-12 placeholder-n-slate-8 focus:outline-none focus:border-n-brand resize-none"
          />
          <p v-if="noteSaveError" class="text-n-ruby-11 text-xs mt-1">
            {{ noteSaveError }}
          </p>
          <div class="flex gap-2 mt-1.5">
            <button
              class="flex-1 flex items-center justify-center gap-1 rounded bg-n-brand px-2 py-1 text-white text-xs font-medium hover:bg-n-brand/90 disabled:opacity-60 transition-colors"
              :disabled="isSavingNote || !noteContent.trim()"
              @click="saveNote"
            >
              <Spinner v-if="isSavingNote" size="12" />
              {{
                isSavingNote
                  ? $t('INTEGRATION_SETTINGS.ZOHO_CRM.SAVING_NOTE')
                  : $t('INTEGRATION_SETTINGS.ZOHO_CRM.SAVE_NOTE')
              }}
            </button>
            <button
              class="rounded px-2 py-1 text-n-slate-9 text-xs hover:text-n-slate-12 transition-colors"
              @click="cancelNote"
            >
              {{ $t('INTEGRATION_SETTINGS.ZOHO_CRM.CANCEL') }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
