import { computed, unref } from 'vue';
import { useNow } from '@vueuse/core';

/**
 * Reactive countdown to a future unix timestamp (seconds), updating every second.
 * @param {import('vue').Ref<number|null|undefined> | (() => number|null|undefined)} expiresAtSeconds
 * @returns {{ remainingSeconds: import('vue').ComputedRef<number|null>, formatted: import('vue').ComputedRef<string|null> }}
 */
export function useCountdown(expiresAtSeconds) {
  const now = useNow({ interval: 1000 });

  const remainingSeconds = computed(() => {
    const expiresAt = unref(expiresAtSeconds);
    if (!expiresAt) return null;

    const diff = expiresAt - Math.floor(now.value.getTime() / 1000);
    return diff > 0 ? diff : null;
  });

  const formatted = computed(() => {
    const seconds = remainingSeconds.value;
    if (seconds === null) return null;

    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);

    if (hours > 0) return `${hours}h ${minutes}m`;
    if (minutes > 0) return `${minutes}m`;
    return `${seconds % 60}s`;
  });

  return { remainingSeconds, formatted };
}
