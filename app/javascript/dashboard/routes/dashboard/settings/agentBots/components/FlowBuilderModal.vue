<script setup>
import { ref, computed, watch } from 'vue';
import Draggable from 'vuedraggable';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import FlowStep from './FlowStep.vue';
import { FLOW_TEMPLATES } from './flowTemplates.js';

const props = defineProps({
  modelValue: { type: String, default: '' },
});

const emit = defineEmits(['update:modelValue']);

const dialogRef = ref(null);
const variables = ref([]);
const steps = ref([]);
const initialStep = ref('');
const reactivation = ref({ enabled: false, message: '' });
const zohoCheck = ref({ enabled: false, not_found_initial_step: '' });

// ── Modo JSON ─────────────────────────────────────────────────────────────────
const activeTab = ref('visual'); // 'visual' | 'json'
const rawJson = ref('');
const jsonError = ref('');

const switchToJson = () => {
  rawJson.value = generateConfig();
  jsonError.value = '';
  activeTab.value = 'json';
};

const switchToVisual = () => {
  try {
    JSON.parse(rawJson.value); // validar antes de parsear
    parseConfig(rawJson.value);
    jsonError.value = '';
    activeTab.value = 'visual';
  } catch {
    jsonError.value = 'JSON inválido — revisa la sintaxis antes de cambiar a visual.';
  }
};

const uid = () => Math.random().toString(36).slice(2);

// ── Parse JSON → internal state ───────────────────────────────────────────────
const parseConfig = json => {
  try {
    const c = json ? JSON.parse(json) : {};
    variables.value = Object.entries(c.variables || {}).map(([key, value]) => ({
      id: uid(), key, value,
    }));
    steps.value = Object.entries(c.steps || {}).map(([name, s]) => ({
      id: uid(),
      name,
      message: s.message || '',
      action: s.action || '',
      capture: s.capture || '',
      transitions: (s.transitions || []).map(tr => {
        const w = tr.when || {};
        return {
          id: uid(),
          type: w.default ? 'default' : w.contains ? 'contains' : w.equals ? 'equals' : 'starts_with',
          value: w.default ? '' : w.contains ? w.contains.join(', ') : (w.equals ?? w.starts_with ?? ''),
          nextStep: tr.next_step || '',
        };
      }),
    }));
    initialStep.value = c.initial_step || steps.value[0]?.name || '';
    reactivation.value = {
      enabled: c.reactivation?.enabled === true,
      message: c.reactivation?.message || '',
    };
    zohoCheck.value = {
      enabled: c.zoho_check?.enabled === true,
      not_found_initial_step: c.zoho_check?.not_found_initial_step || '',
    };
  } catch {
    variables.value = [];
    steps.value = [];
    initialStep.value = '';
    reactivation.value = { enabled: false, message: '' };
  }
};

// ── Internal state → JSON ─────────────────────────────────────────────────────
const generateConfig = () => {
  const vars = {};
  variables.value.forEach(v => {
    if (v.key.trim()) vars[v.key.trim()] = v.value;
  });

  const stepsObj = {};
  steps.value.forEach(s => {
    if (!s.name.trim()) return;
    const sd = {};
    if (s.message) sd.message = s.message;
    if (s.action) sd.action = s.action;
    if (s.capture && s.capture.trim()) sd.capture = s.capture.trim();
    const transitions = s.transitions
      .filter(t => t.nextStep)
      .map(t => {
        const when = {};
        if (t.type === 'default') when.default = true;
        else if (t.type === 'contains') when.contains = t.value.split(',').map(w => w.trim()).filter(Boolean);
        else if (t.type === 'equals') when.equals = t.value.trim();
        else when.starts_with = t.value.trim();
        return { when, next_step: t.nextStep };
      });
    if (transitions.length) sd.transitions = transitions;
    stepsObj[s.name.trim()] = sd;
  });

  const config = { variables: vars, initial_step: initialStep.value, steps: stepsObj };

  if (reactivation.value.enabled && reactivation.value.message.trim()) {
    config.reactivation = {
      enabled: true,
      message: reactivation.value.message.trim(),
    };
  }

  if (zohoCheck.value.enabled) {
    config.zoho_check = {
      enabled: true,
      not_found_initial_step: zohoCheck.value.not_found_initial_step.trim(),
    };
  }

  return JSON.stringify(config, null, 2);
};

// ── Computed ──────────────────────────────────────────────────────────────────
const stepNames = computed(() => steps.value.map(s => s.name.trim()).filter(Boolean));
const stepCount = computed(() => steps.value.filter(s => s.name.trim()).length);
const variableCount = computed(() => variables.value.filter(v => v.key.trim()).length);

// ── Variables ─────────────────────────────────────────────────────────────────
const addVariable = () => variables.value.push({ id: uid(), key: '', value: '' });
const removeVariable = i => variables.value.splice(i, 1);

// ── Steps ─────────────────────────────────────────────────────────────────────
const addStep = () => {
  steps.value.push({ id: uid(), name: '', message: '', action: '', transitions: [] });
};

const removeStep = i => {
  const [removed] = steps.value.splice(i, 1);
  if (initialStep.value === removed.name.trim()) {
    initialStep.value = steps.value[0]?.name.trim() || '';
  }
};

const updateStep = (i, updated) => { steps.value[i] = updated; };
const setInitial = name => { initialStep.value = name; };

// ── Save / expose ─────────────────────────────────────────────────────────────
const handleSave = () => {
  if (activeTab.value === 'json') {
    try {
      JSON.parse(rawJson.value);
      emit('update:modelValue', rawJson.value);
      dialogRef.value.close();
    } catch {
      jsonError.value = 'JSON inválido — corrige la sintaxis antes de guardar.';
    }
    return;
  }
  emit('update:modelValue', generateConfig());
  dialogRef.value.close();
};

// ── Templates ─────────────────────────────────────────────────────────────────
const isEmpty = computed(
  () => steps.value.length === 0 && variables.value.length === 0
);

const loadTemplate = tpl => {
  parseConfig(JSON.stringify(tpl.config));
};

const open = () => dialogRef.value.open();

watch(() => props.modelValue, parseConfig, { immediate: true });

defineExpose({ dialogRef: { open, close: () => dialogRef.value.close() } });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    title="Configurar flujo del bot"
    description="Define los pasos, mensajes y transiciones. El JSON se genera automáticamente."
    :show-cancel-button="false"
    :show-confirm-button="false"
    width="3xl"
    position="top"
    overflow-y-auto
  >
    <div class="flex flex-col gap-6">

      <!-- ── Tabs Visual / JSON ────────────────────────────────────────────── -->
      <div class="flex items-center gap-1 rounded-lg border border-n-weak bg-n-alpha-1 p-1 self-start">
        <button
          type="button"
          class="flex items-center gap-1.5 rounded-md px-3 py-1.5 text-xs font-medium transition-colors"
          :class="activeTab === 'visual'
            ? 'bg-white shadow text-n-slate-12 dark:bg-n-slate-4'
            : 'text-n-slate-9 hover:text-n-slate-11'"
          @click="activeTab === 'json' ? switchToVisual() : null"
        >
          <span class="i-lucide-layers h-3.5 w-3.5" />
          Visual
        </button>
        <button
          type="button"
          class="flex items-center gap-1.5 rounded-md px-3 py-1.5 text-xs font-medium transition-colors"
          :class="activeTab === 'json'
            ? 'bg-white shadow text-n-slate-12 dark:bg-n-slate-4'
            : 'text-n-slate-9 hover:text-n-slate-11'"
          @click="activeTab === 'visual' ? switchToJson() : null"
        >
          <span class="i-lucide-braces h-3.5 w-3.5" />
          JSON
        </button>
      </div>

      <!-- ── Panel JSON ────────────────────────────────────────────────────── -->
      <template v-if="activeTab === 'json'">
        <div class="flex flex-col gap-2">
          <div class="flex items-center justify-between">
            <div>
              <p class="text-sm font-semibold text-n-slate-12">Editor JSON</p>
              <p class="text-xs text-n-slate-9">Pega o edita el JSON del flujo directamente. Cambia a <strong>Visual</strong> para validar y convertir.</p>
            </div>
            <NextButton
              size="sm"
              variant="outline"
              icon="i-lucide-layers"
              label="Ver visual"
              type="button"
              @click="switchToVisual"
            />
          </div>
          <textarea
            v-model="rawJson"
            rows="28"
            spellcheck="false"
            class="w-full resize-y rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 font-mono text-xs text-n-slate-12 placeholder-n-slate-8 focus:border-n-brand focus:outline-none min-h-[320px]"
            placeholder='{"variables":{},"initial_step":"bienvenida","steps":{"bienvenida":{"message":"Hola!","transitions":[]}}}'
            @input="jsonError = ''"
          />
          <p v-if="jsonError" class="text-xs text-n-ruby-11 flex items-center gap-1">
            <span class="i-lucide-alert-circle h-3.5 w-3.5" />
            {{ jsonError }}
          </p>
          <p v-else class="text-[11px] text-n-slate-9">
            El JSON se validará al guardar o al cambiar a modo visual.
          </p>
        </div>

        <!-- Footer en modo JSON -->
        <div class="flex items-center justify-end gap-2 border-t border-n-weak pt-4">
          <NextButton faded slate size="sm" type="button" label="Cancelar" @click="dialogRef.close()" />
          <NextButton size="sm" type="button" icon="i-lucide-check" label="Guardar flujo" @click="handleSave" />
        </div>
      </template>

      <!-- ── Panel Visual ──────────────────────────────────────────────────── -->
      <template v-else>

      <!-- ── Plantillas ─────────────────────────────────────────────────────── -->
      <section v-if="isEmpty" class="flex flex-col gap-3">
        <div>
          <h3 class="text-sm font-semibold text-n-slate-12">Comenzar desde una plantilla</h3>
          <p class="text-xs text-n-slate-9">Elige una plantilla lista para usar o empieza desde cero con los pasos de abajo.</p>
        </div>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <button
            v-for="tpl in FLOW_TEMPLATES"
            :key="tpl.id"
            type="button"
            class="flex items-start gap-3 rounded-xl border border-n-weak bg-n-alpha-1 p-4 text-left transition-colors hover:border-n-blue-7 hover:bg-n-blue-2"
            @click="loadTemplate(tpl)"
          >
            <span :class="[tpl.icon, 'mt-0.5 h-5 w-5 shrink-0 text-n-blue-10']" />
            <div class="min-w-0">
              <p class="text-sm font-semibold text-n-slate-12">{{ tpl.name }}</p>
              <p class="mt-0.5 text-xs text-n-slate-9 leading-relaxed">{{ tpl.description }}</p>
            </div>
          </button>
        </div>
        <div class="flex items-center gap-3">
          <div class="h-px flex-1 bg-n-weak" />
          <span class="text-xs text-n-slate-8">o empieza desde cero</span>
          <div class="h-px flex-1 bg-n-weak" />
        </div>
      </section>

      <!-- Banner cuando ya hay contenido -->
      <div v-else class="flex items-center justify-between rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2">
        <p class="text-xs text-n-slate-9">¿Quieres partir de una plantilla?</p>
        <div class="flex gap-1">
          <button
            v-for="tpl in FLOW_TEMPLATES"
            :key="tpl.id"
            type="button"
            class="rounded px-2 py-1 text-xs text-n-blue-10 hover:bg-n-blue-3"
            @click="loadTemplate(tpl)"
          >
            {{ tpl.name.split('—')[0].trim() }}
          </button>
        </div>
      </div>

      <!-- ── Variables ──────────────────────────────────────────────────────── -->
      <section class="flex flex-col gap-3">
        <div class="flex items-center justify-between">
          <div>
            <h3 class="text-sm font-semibold text-n-slate-12">Variables</h3>
            <p class="text-xs text-n-slate-9">
              Valores reutilizables que puedes insertar en los mensajes con
              <code class="rounded bg-n-alpha-3 px-1 font-mono">&#123;&#123;nombre&#125;&#125;</code>
            </p>
          </div>
          <NextButton size="sm" variant="outline" icon="i-lucide-plus" label="Agregar variable" type="button" @click="addVariable" />
        </div>

        <div v-if="variables.length" class="flex flex-col gap-2">
          <div v-for="(v, i) in variables" :key="v.id" class="flex items-center gap-2">
            <input
              v-model="v.key"
              placeholder="nombre_variable"
              class="w-44 rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 font-mono text-xs text-n-slate-12 placeholder-n-slate-8 focus:border-n-brand focus:outline-none"
              spellcheck="false"
            />
            <span class="text-xs text-n-slate-8">=</span>
            <input
              v-model="v.value"
              placeholder="Valor"
              class="flex-1 rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 placeholder-n-slate-8 focus:border-n-brand focus:outline-none"
            />
            <button class="rounded p-1 text-n-slate-8 hover:bg-n-ruby-3 hover:text-n-ruby-11" @click="removeVariable(i)">
              <span class="i-lucide-x h-4 w-4" />
            </button>
          </div>
        </div>
        <p v-else class="text-xs italic text-n-slate-8">Sin variables — agrégalas si quieres personalizar mensajes.</p>
      </section>

      <div class="h-px bg-n-weak" />

      <!-- ── Pasos ───────────────────────────────────────────────────────────── -->
      <section class="flex flex-col gap-3">
        <div class="flex items-center justify-between">
          <div>
            <h3 class="text-sm font-semibold text-n-slate-12">
              Pasos del flujo
              <span v-if="stepCount" class="ml-1.5 rounded-full bg-n-alpha-3 px-2 py-0.5 text-xs font-normal text-n-slate-10">
                {{ stepCount }}
              </span>
            </h3>
            <p class="text-xs text-n-slate-9">
              Paso inicial:
              <span class="font-mono font-medium text-n-blue-11">{{ initialStep || 'sin definir' }}</span>
            </p>
          </div>
          <NextButton size="sm" variant="outline" icon="i-lucide-plus" label="Agregar paso" type="button" @click="addStep" />
        </div>

        <Draggable
          v-if="steps.length"
          v-model="steps"
          item-key="id"
          animation="200"
          handle=".flow-step-drag-handle"
          class="flex flex-col gap-3"
          ghost-class="opacity-40"
        >
          <template #item="{ element: step, index: i }">
            <FlowStep
              :step="step"
              :step-names="stepNames"
              :is-initial="initialStep === step.name.trim() && step.name.trim() !== ''"
              :index="i"
              @update:step="updateStep(i, $event)"
              @remove="removeStep(i)"
              @set-initial="setInitial"
            />
          </template>
        </Draggable>

        <div v-else class="flex flex-col items-center gap-2 rounded-xl border border-dashed border-n-weak py-10 text-center">
          <span class="i-lucide-git-branch h-8 w-8 text-n-slate-8" />
          <p class="text-sm text-n-slate-9">
            Sin pasos todavía.<br />Haz clic en <strong>Agregar paso</strong> para comenzar.
          </p>
        </div>
      </section>

      <div class="h-px bg-n-weak" />

      <!-- ── Verificación Zoho CRM ─────────────────────────────────────────── -->
      <section class="flex flex-col gap-3">
        <div class="flex items-center justify-between">
          <div>
            <h3 class="text-sm font-semibold text-n-slate-12">Verificación Zoho CRM</h3>
            <p class="text-xs text-n-slate-9">
              Si está activo, el bot consulta Zoho al inicio. Leads conocidos van al flujo principal;
              los desconocidos van al flujo de calificación.
            </p>
          </div>
          <button
            type="button"
            class="relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 focus:outline-none"
            :class="zohoCheck.enabled ? 'bg-n-blue-9' : 'bg-n-slate-5'"
            @click="zohoCheck.enabled = !zohoCheck.enabled"
          >
            <span
              class="pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out"
              :class="zohoCheck.enabled ? 'translate-x-4' : 'translate-x-0'"
            />
          </button>
        </div>

        <div v-if="zohoCheck.enabled" class="flex flex-col gap-3">
          <div class="flex items-start gap-2 rounded-lg border border-n-blue-6 bg-n-blue-2 px-3 py-2">
            <span class="i-lucide-info mt-0.5 h-4 w-4 shrink-0 text-n-blue-10" />
            <p class="text-xs text-n-blue-11">
              Crea pasos de calificación (ej: <code class="font-mono">calificar_nombre</code>, <code class="font-mono">calificar_razon</code>, <code class="font-mono">calificar_timeline</code>) con el campo <strong>Capturar respuesta</strong> activado, y aquí indica cuál es el primero.
            </p>
          </div>
          <div class="flex items-center gap-3">
            <label class="shrink-0 text-xs font-semibold text-n-slate-11">Si no está en Zoho, iniciar en:</label>
            <select
              v-model="zohoCheck.not_found_initial_step"
              class="flex-1 rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 focus:border-n-brand focus:outline-none"
            >
              <option value="">— igual al flujo principal —</option>
              <option v-for="name in stepNames" :key="name" :value="name">{{ name }}</option>
            </select>
          </div>
        </div>

        <div v-else class="rounded-lg border border-dashed border-n-weak px-4 py-3">
          <p class="text-xs italic text-n-slate-8">
            Verificación Zoho desactivada — todos los leads entran al flujo principal.
          </p>
        </div>
      </section>

      <div class="h-px bg-n-weak" />

      <!-- ── Reactivación ────────────────────────────────────────────────────── -->
      <section class="flex flex-col gap-3">
        <div class="flex items-center justify-between">
          <div>
            <h3 class="text-sm font-semibold text-n-slate-12">Mensaje de reactivación</h3>
            <p class="text-xs text-n-slate-9">
              Se envía automáticamente antes de que cierre la ventana de 24h de Meta
              si el lead no respondió.
            </p>
          </div>
          <!-- Toggle -->
          <button
            type="button"
            class="relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 focus:outline-none"
            :class="reactivation.enabled ? 'bg-n-blue-9' : 'bg-n-slate-5'"
            @click="reactivation.enabled = !reactivation.enabled"
          >
            <span
              class="pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out"
              :class="reactivation.enabled ? 'translate-x-4' : 'translate-x-0'"
            />
          </button>
        </div>

        <div v-if="reactivation.enabled" class="flex flex-col gap-2">
          <!-- Timing info -->
          <div class="flex items-start gap-2 rounded-lg border border-n-amber-6 bg-n-amber-3 px-3 py-2">
            <span class="i-lucide-clock mt-0.5 h-4 w-4 shrink-0 text-n-amber-11" />
            <p class="text-xs text-n-amber-11">
              El sistema manda este mensaje si el lead lleva entre <strong>20 y 23 horas</strong> sin
              responder — dejando margen antes del cierre de la ventana de Meta. Solo se manda
              <strong>una vez</strong> por conversación.
            </p>
          </div>

          <!-- Message textarea -->
          <textarea
            v-model="reactivation.message"
            rows="4"
            placeholder="Ejemplo: ¡Hola! 👋 Notamos que no hemos podido conectarte con un asesor. ¿Sigues interesado en conocer {{desarrollo}}? Solo responde a este mensaje y con gusto te atendemos."
            class="w-full resize-y rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 placeholder-n-slate-8 focus:border-n-brand focus:outline-none"
          />
          <p class="text-[11px] text-n-slate-9">
            Puedes usar <code class="rounded bg-n-alpha-3 px-1 font-mono">&#123;&#123;variables&#125;&#125;</code> del flujo.
            El mensaje debe ser breve y con una pregunta clara para que el lead responda.
          </p>
        </div>

        <div v-else class="rounded-lg border border-dashed border-n-weak px-4 py-3">
          <p class="text-xs italic text-n-slate-8">
            Reactivación desactivada — activa el toggle para configurarla.
          </p>
        </div>
      </section>

      <!-- ── Footer ─────────────────────────────────────────────────────────── -->
      <div class="flex items-center justify-between border-t border-n-weak pt-4">
        <p class="text-xs text-n-slate-9">
          <span class="font-medium">{{ stepCount }}</span> pasos ·
          <span class="font-medium">{{ variableCount }}</span> variables ·
          reactivación
          <span :class="reactivation.enabled ? 'text-n-blue-10 font-medium' : 'italic'">
            {{ reactivation.enabled ? 'activa' : 'inactiva' }}
          </span>
        </p>
        <div class="flex gap-2">
          <NextButton faded slate size="sm" type="button" label="Cancelar" @click="dialogRef.close()" />
          <NextButton size="sm" type="button" icon="i-lucide-check" label="Guardar flujo" @click="handleSave" />
        </div>
      </div>

      </template><!-- fin panel visual -->

    </div>
  </Dialog>
</template>
