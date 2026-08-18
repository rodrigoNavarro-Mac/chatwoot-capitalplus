<script setup>
defineProps({
  text: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <p v-if="text" class="text-xs text-n-slate-11 italic mb-3">
    {{ text }}
  </p>
</template>
