<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed } from 'vue';

const props = defineProps({
  step: { type: Object, required: true },
  stepNames: { type: Array, default: () => [] },
  isInitial: { type: Boolean, default: false },
});

const emit = defineEmits(['update:step', 'remove', 'setInitial']);

const ACTIONS = [
  { value: '', label: 'Sin acción (continúa el flujo)' },
  { value: 'open_conversation', label: 'Transferir a agente humano' },
  { value: 'resolve_conversation', label: 'Resolver y cerrar conversación' },
];

const CONDITION_TYPES = [
  { value: 'contains', label: 'Contiene' },
  { value: 'equals', label: 'Es exactamente' },
  { value: 'starts_with', label: 'Empieza con' },
  { value: 'default', label: 'Por defecto (fallback)' },
];

const uid = () => Math.random().toString(36).slice(2);

const patch = (field, value) =>
  emit('update:step', { ...props.step, [field]: value });

const addTransition = () => {
  emit('update:step', {
    ...props.step,
    transitions: [
      ...props.step.transitions,
      { id: uid(), type: 'contains', value: '', nextStep: '' },
    ],
  });
};

const patchTransition = (i, field, value) => {
  const updated = props.step.transitions.map((t, idx) =>
    idx === i ? { ...t, [field]: value } : t
  );
  emit('update:step', { ...props.step, transitions: updated });
};

const removeTransition = i => {
  emit('update:step', {
    ...props.step,
    transitions: props.step.transitions.filter((_, idx) => idx !== i),
  });
};

const hasTerminalAction = computed(
  () =>
    props.step.action === 'open_conversation' ||
    props.step.action === 'resolve_conversation'
);
</script>

<template>
  <div
    class="flex flex-col rounded-xl border bg-n-alpha-2 transition-colors"
    :class="isInitial ? 'border-n-blue-7' : 'border-n-weak'"
  >
    <!-- Header -->
    <div class="flex items-center gap-2 px-4 py-3">
      <span
        class="flow-step-drag-handle i-lucide-grip-vertical h-4 w-4 shrink-0 cursor-grab text-n-slate-8 hover:text-n-slate-11"
      />

      <span
        v-if="isInitial"
        class="shrink-0 rounded-full bg-n-blue-4 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-n-blue-11"
      >
        Inicio
      </span>

      <input
        :value="step.name"
        placeholder="nombre_del_paso"
        class="min-w-0 flex-1 rounded-md border border-transparent bg-transparent px-2 py-1 font-mono text-sm font-medium text-n-slate-12 placeholder-n-slate-8 hover:border-n-weak focus:border-n-brand focus:bg-n-alpha-1 focus:outline-none"
        spellcheck="false"
        @input="patch('name', $event.target.value)"
      />

      <div class="flex shrink-0 items-center gap-1">
        <button
          v-if="!isInitial && step.name.trim()"
          title="Usar como paso inicial"
          class="rounded px-2 py-1 text-xs text-n-blue-10 hover:bg-n-blue-3 hover:text-n-blue-12"
          @click="$emit('setInitial', step.name.trim())"
        >
          ↑ Inicial
        </button>
        <button
          title="Eliminar paso"
          class="rounded p-1 text-n-slate-8 hover:bg-n-ruby-3 hover:text-n-ruby-11"
          @click="$emit('remove')"
        >
          <span class="i-lucide-trash-2 h-3.5 w-3.5" />
        </button>
      </div>
    </div>

    <div class="mx-4 h-px bg-n-weak" />

    <!-- Body -->
    <div class="flex flex-col gap-4 px-4 py-4">
      <!-- Message -->
      <div class="flex flex-col gap-1.5">
        <label class="text-xs font-semibold text-n-slate-11"
          >Mensaje del bot</label
        >
        <textarea
          :value="step.message"
          rows="6"
          placeholder="Escribe el mensaje que enviará el bot al cliente…"
          class="w-full resize-y rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 placeholder-n-slate-8 focus:border-n-brand focus:outline-none"
          @input="patch('message', $event.target.value)"
        />
        <p class="text-[11px] text-n-slate-9">
          Usa
          <code class="rounded bg-n-alpha-3 px-1 font-mono"
            >&#123;&#123;nombre_variable&#125;&#125;</code
          >
          para insertar variables.
        </p>
      </div>

      <!-- Capture -->
      <div class="flex flex-col gap-1.5">
        <label class="text-xs font-semibold text-n-slate-11"
          >Capturar respuesta del usuario</label
        >
        <div class="flex items-center gap-2">
          <span class="text-xs text-n-slate-9 shrink-0">Guardar como</span>
          <input
            :value="step.capture"
            placeholder="ej: lead_nombre  (dejar vacío si no aplica)"
            class="flex-1 rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 font-mono text-xs text-n-slate-12 placeholder-n-slate-8 focus:border-n-brand focus:outline-none"
            spellcheck="false"
            @input="patch('capture', $event.target.value)"
          />
        </div>
        <p class="text-[11px] text-n-slate-9">
          La respuesta del cliente a este paso se guardará en
          <code class="rounded bg-n-alpha-3 px-1 font-mono"
            >&#123;&#123;lead_nombre&#125;&#125;</code
          >
          y podrá usarse en mensajes posteriores.
        </p>
      </div>

      <!-- Action -->
      <div class="flex flex-col gap-1.5">
        <label class="text-xs font-semibold text-n-slate-11"
          >Acción al enviar</label
        >
        <select
          :value="step.action"
          class="rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 focus:border-n-brand focus:outline-none"
          @change="patch('action', $event.target.value)"
        >
          <option v-for="a in ACTIONS" :key="a.value" :value="a.value">
            {{ a.label }}
          </option>
        </select>
      </div>

      <!-- Transitions -->
      <div class="flex flex-col gap-2">
        <div class="flex items-center justify-between">
          <label class="text-xs font-semibold text-n-slate-11"
            >Transiciones</label
          >
          <button
            v-if="!hasTerminalAction"
            class="flex items-center gap-1 rounded px-2 py-1 text-xs font-medium text-n-blue-10 hover:bg-n-blue-3"
            @click="addTransition"
          >
            <span class="i-lucide-plus h-3 w-3" />
            Agregar
          </button>
        </div>

        <p v-if="hasTerminalAction" class="text-xs italic text-n-slate-9">
          Este paso termina la conversación — no necesita transiciones.
        </p>

        <template v-else>
          <div
            v-for="(tr, i) in step.transitions"
            :key="tr.id"
            class="flex flex-wrap items-center gap-2 rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2"
          >
            <select
              :value="tr.type"
              class="rounded-md border border-n-weak bg-n-solid-1 px-2 py-1 text-xs text-n-slate-12 focus:border-n-brand focus:outline-none"
              @change="patchTransition(i, 'type', $event.target.value)"
            >
              <option
                v-for="ct in CONDITION_TYPES"
                :key="ct.value"
                :value="ct.value"
              >
                {{ ct.label }}
              </option>
            </select>

            <input
              v-if="tr.type !== 'default'"
              :value="tr.value"
              :placeholder="
                tr.type === 'contains' ? 'sí, si, yes, 1' : 'texto exacto'
              "
              class="min-w-0 flex-1 rounded-md border border-n-weak bg-n-solid-1 px-2 py-1 text-xs text-n-slate-12 placeholder-n-slate-8 focus:border-n-brand focus:outline-none"
              @input="patchTransition(i, 'value', $event.target.value)"
            />
            <div v-else class="flex-1 text-xs italic text-n-slate-8">
              cualquier respuesta
            </div>

            <span class="shrink-0 text-xs text-n-slate-8">→</span>

            <select
              :value="tr.nextStep"
              class="rounded-md border border-n-weak bg-n-solid-1 px-2 py-1 text-xs text-n-slate-12 focus:border-n-brand focus:outline-none"
              :class="{ 'border-n-ruby-7': !tr.nextStep }"
              @change="patchTransition(i, 'nextStep', $event.target.value)"
            >
              <option value="">— paso destino —</option>
              <option v-for="name in stepNames" :key="name" :value="name">
                {{ name }}
              </option>
            </select>

            <button
              class="shrink-0 rounded p-1 text-n-slate-8 hover:text-n-ruby-10"
              @click="removeTransition(i)"
            >
              <span class="i-lucide-x h-3 w-3" />
            </button>
          </div>

          <p
            v-if="!step.transitions.length"
            class="text-xs italic text-n-slate-8"
          >
            Sin transiciones — al recibir respuesta regresa al paso inicial.
          </p>
        </template>
      </div>
    </div>
  </div>
</template>
